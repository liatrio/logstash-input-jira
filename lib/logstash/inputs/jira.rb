# encoding: utf-8
require "logstash/inputs/base"
require 'logstash/plugin_mixins/http_client'
require 'logstash/event'
require 'logstash/json'
require "stud/interval"
require "socket" # for Socket.gethostname
require "rufus/scheduler"
require "json"
require 'elasticsearch'

class LogStash::Inputs::Jira < LogStash::Inputs::Base
  include LogStash::PluginMixins::HttpClient

  config_name "jira"

  # If undefined, Logstash will complain, even if codec is unused.
  default :codec, "json"

  # Schedule of when to periodically poll from the urls
  # Format: A hash with
  #   + key: "cron" | "every" | "in" | "at"
  #   + value: string
  # Examples:
  #   a) { "every" => "1h" }
  #   b) { "cron" => "* * * * * UTC" }
  # See: rufus/scheduler for details about different schedule options and value string format
  config :schedule, :validate => :hash, :required => true

  config :scheme, :validate => :string, :default => 'http'

  config :jira_hostname, :validate => :string, :default => 'localhost'

  config :port, :validate => :number, :default => 80

  config :token, :validate => :string, :required => true

  config :elastic_scheme, :validate => :string, :default => 'http'

  config :elastic_port, :validate => :number, :default => 9200

  config :elastic_host, :validate => :string, :default => 'elasticsearch'

  public

  Schedule_types = %w(cron every at in)

  def register
    @host = Socket.gethostname.force_encoding(Encoding::UTF_8)
    @authorization = "Basic #{@token}"
    @logger.info('Register Jira Input', :schedule => @schedule, :jira_hostname => @jira_hostname, :port => @port)
  end

  def run(queue)
    @logger.info('RUN')
    #schedule hash must contain exactly one of the allowed keys
    msg_invalid_schedule = "Invalid config. schedule hash must contain " +
        "exactly one of the following keys - cron, at, every or in"
    raise Logstash::ConfigurationError, msg_invalid_schedule if @schedule.keys.length != 1
    schedule_type = @schedule.keys.first
    schedule_value = @schedule[schedule_type]
    raise LogStash::ConfigurationError, msg_invalid_schedule unless Schedule_types.include?(schedule_type)

    @scheduler = Rufus::Scheduler.new(:max_work_threads => 1)
    #as of v3.0.9, :first_in => :now doesn't work. Use the following workaround instead
    opts = schedule_type == "every" ? {:first_in => 0.01} : {}
    @scheduler.send(schedule_type, schedule_value, opts) {run_once(queue)}
    @scheduler.join
  end

  def run_once(queue)
    @logger.info('RUN ONCE')

    request_jira_issues(
        queue,
        'rest/api/2/search',
        {},
        {},
       'handle_issues_response')

    client.execute!
  end

  ## BASE API CALL AGAINST JIRA API TO GET LIST OF ISSUES
  def request_jira_issues(queue, path, parameters, request_options, callback)
    started = Time.now

    method = parameters[:method] ? parameters.delete(:method) : :get

    uri = "http://#{@jira_hostname}/#{path}" % parameters

    request_options[:headers] = {'Authorization' => @authorization}

    client.parallel.send(method, uri, request_options).
        on_success {|response| self.send(callback, queue, uri, parameters, response, Time.now - started)}.
        on_failure {|exception|
          handle_failure(queue, uri, parameters, exception, Time.now - started)
        }
  end

  ## BASE API AGAINST ELASTICSEARCH SERVER TO GET DOCS ALREADY IN ELASTICSEARCH
  def request_es_docs(queue, path, parameters, request_options, callback)

    started = Time.now

    method = parameters[:method] ? parameters.delete(:method) : :get

    uri = "#{@elastic_scheme}://#{@elastic_host}:#{@elastic_port}/#{path}"

    client.parallel.send(method, uri, request_options).
        on_success {|response| self.send(callback, queue, uri, parameters, response, Time.now - started)}.
        on_failure {|exception|
          handle_failure(queue, uri, parameters, exception, Time.now - started)
        }
  end

  ## JIRA DEV API TO GET LINKED REPOS TO ISSUES
  def request_issue_repos(queue, path, parameters, request_options, callback)

    started = Time.now

    method = parameters[:method] ? parameters.delete(:method) : :get

    uri = "http://jira.liatr.io/rest/dev-status/1.0/issue/detail?issueId=#{path}&applicationType=stash&dataType=repository"

    request_options[:headers] = {'Authorization' => @authorization}

    client.parallel.send(method, uri, request_options).
        on_success {|response| self.send(callback, queue, uri, parameters, response, Time.now - started)}.
        on_failure {|exception|
          handle_failure(queue, uri, parameters, exception, Time.now - started)
        }
  end

  ## CALL TO ADD ALL ISSUES INTO QUEUE AND CHECK EACH ISSUE TO SEE IF THEY ARE ALREADY IN ES
  def handle_issues_response(queue, uri, parameters, response, execution_time)
    # Decode JSON
    body = JSON.parse(response.body)

    @logger.info("Handle Issues Response", :uri => uri, :start => body['startAt'], :size => body['total'])
    nextStartAt = body['startAt'] + body['maxResults']
    request_count = 0

    # Fetch addition project pages
    unless body['total'] < nextStartAt
      request_jira_issues(
          queue,
          "rest/api/2/search",
          {},
          {:query => {'startAt' => nextStartAt}},
          'handle_issues_response'
      )

      client.execute!
    end

    # Iterate over each project
    body['issues'].each do |issue|
      #@logger.info("Add Issue", :issue => issue['key'])

      request_es_docs(
          queue,
          "issue/doc/#{issue['key']}",
          {:issueId => issue['id'], :issueName => issue['key']},
          {},
          'check_issue_exists')

      request_count += 1

      if request_count > 1
       request_count = 0
       client.execute!
      end

    end
  end


  ## FUNCTION THAT CHECK IF ISSUE ALREADY EXISTS
  # IF DOESN'T EXISTS MAKES CALL TO ADD ISSUE
  # IF EXISTS CHECKS IF LEAD EXISTS AND CHECKS LAST UPDATE ON ISSUE
  def check_issue_exists(queue, uri, parameters, response, execution_time)

    body = JSON.parse(response.body)

    if body['found'] == false
      request_jira_issues(
          queue,
          "rest/api/2/search?jql=key=%{issue}",
          {:issue => body['_id']},
          {},
          'add_issue')

    else
      request_es_docs(
          queue,
          "lead_time/doc/lead-#{parameters[:issueName]}",
          {:issueId => parameters[:issueId], :issueName => parameters[:issueName], :createdDate => body['_source']['fields']['updated']},
          {},
          'check_lead_exists')

      request_jira_issues(
          queue,
          "rest/api/2/search?jql=key=%{issue}",
          {:issue => body['_id'], :createdDate => body['_source']['fields']['updated']},
          {},
          'check_last_update')
    end
  end

  ## CHECKS IF LEAT TIME DOC ALREADY EXISTS
  # IF IT DOES NOT CREATE NEW LEAD TIME DOC
  def check_lead_exists(queue, uri, parameters, response, execution_time)

    body = JSON.parse(response.body)

    if body['found'] == false

      request_issue_repos(
          queue,
          parameters[:issueId],
          {:id => parameters[:issueId], :issueName => parameters[:issueName], :createdDate => parameters[:createdDate]},
          {},
          'create_lead_time')

    else
      #PUTS LEAD TIME DOC EXISTS ALREADY DO NOTHING
    end
  end

  ## CHECKS AND SEE'S IF ISSUE HAS BEEN UPDATED AND CHECKS IF ISSUE DOC NEEDS UPDATING
  def check_last_update(queue, uri, parameters, response, execution_time)
    # Decode JSON
    body = JSON.parse(response.body)

    # Iterate over each project
    issue = body['issues'][0]
    date = body['issues'][0]['fields']['updated']

    if date == parameters[:createdDate]
      #DOC HASN'T BEEN UPDATED DO NOTHING
    else
      #Push project event into queue
      event = LogStash::Event.new(issue)
      event.set('[@metadata][index]', 'issue')
      event.set('[@metadata][id]', issue['key'])
      queue << event
    end
  end

  ## CREATES ISSUE AND ADDS IT TO ELASTICSEARCH
  def add_issue(queue, uri, parameters, response, execution_time)
    # Decode JSON
    body = JSON.parse(response.body)

    # Iterate over each project
    issue = body['issues'][0]
    @logger.info("Add Issue", :issue => issue['key'])
      #Push project event into queue
      event = LogStash::Event.new(issue)
      event.set('[@metadata][index]', 'issue')
      event.set('[@metadata][id]', issue['key'])
      queue << event
  end

  ## FETCHES REPO ID TO BE ADDED TO LEAD_TIME DOC
  def fetch_repo_id(queue, uri, parameters, response, execution_time)
    # Decode JSON
    body = JSON.parse(response.body)

    # Iterate over each project
    repo_id = body['hits']['hits'][0]

    return repo_id
  end


  ## CREATES A LEAD TIME DOC TO BE PUSHED TO ELASTICSEARCH
  def create_lead_time(queue, uri, parameters, response, execution_time)

    body = JSON.parse(response.body)

    repoCount = body['detail'][0]['repositories'].count

    if repoCount > 0

      repo_url = body['detail'][0]['repositories'][0]['url']

      client = Elasticsearch::Client.new(:hosts => "#{@elastic_scheme}://#{@elastic_host}:#{@elastic_port}")


      temp = client.search index: 'repo', body: { "query": {
          "bool": {
              "should": [
                  {
                      "nested": {
                          "path": "links.clone",
                          "query": {
                              "term": {
                                  "links.clone.href": {
                                      "value": repo_url
                                  }
                              }
                          }
                      }
                  },
                  {
                      "nested": {
                          "path": "links.self",
                          "query": {
                              "term": {
                                  "links.self.href": {
                                      "value": repo_url
                                  }
                              }
                          }
                      }
                  }
              ]
          }
      }
      }


      #gg = temp['hits']['hits'][0]['_id']

      commits = []

      body['detail'][0]['repositories'][0]['commits'].each do |commit|
        commits.push(commit['id'])
      end


      puts commits


      new_lead = Hash.new
      new_lead["id"] = parameters[:issueName]
      new_lead["created_at"] = parameters[:createdDate]
      #new_lead["repo_id"] =
      #new_lead["repo_id"] = gg
      new_lead["commits"] = commits
      #
      # put commits

      lead = LogStash::Event.new(new_lead)
      lead.set('[@metadata][index]', 'lead_time')
      lead.set('[@metadata][id]', 'lead-' + parameters[:issueName])
      queue << lead

    else
      #puts "NO REPO LINK EXITS TO TICKET"
    end
  end

  def handle_failure(queue, path, parameters, exception, execution_time)
    @logger.error('HTTP Request failed', :path => path, :parameters => parameters, :exception => exception, :backtrace => exception.backtrace);
  end

  def stop
    # nothing to do in this case so it is not necessary to define stop
    # examples of common "stop" tasks:
    #  * close sockets (unblocking blocking reads/accepts)
    #  * cleanup temporary files
    #  * terminate spawned threads
  end

end # class LogStash::Inputs::Jira
