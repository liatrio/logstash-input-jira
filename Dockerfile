FROM docker.elastic.co/logstash/logstash:6.5.4

USER root

RUN yum update -y

USER logstash
ENV PATH=$PATH:/usr/share/logstash/vendor/jruby/bin/
RUN gem install bundler

COPY --chown=logstash:logstash . /usr/share/logstash/plugins/logstash-input-jira

WORKDIR /usr/share/logstash/plugins/logstash-input-jira
RUN bundler install
RUN gem build /usr/share/logstash/plugins/logstash-input-jira/logstash-input-jira.gemspec

WORKDIR /usr/share/logstash
RUN logstash-plugin install /usr/share/logstash/plugins/logstash-input-jira/logstash-input-jira-*.gem
