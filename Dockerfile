<<<<<<< HEAD
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
=======
FROM ruby:onbuild

ENV PORT 3000
EXPOSE 3000

# Ref: https://www.engineyard.com/blog/using-docker-for-rails
RUN mkdir -p /usr/src/app
WORKDIR /usr/src/app

RUN apt-get update && \
    apt-get install -y nodejs mysql-client postgresql-client sqlite3 vim --no-install-recommends && \
    rm -rf /var/lib/apt/lists/*

ENV RAILS_ENV development
ENV RAILS_LOG_TO_STDOUT true

COPY Gemfile /usr/src/app/
COPY Gemfile.lock /usr/src/app/
RUN bundle config --global frozen 1
RUN bundle install --without test

COPY . /usr/src/app

# uncomment this for production
# ENV RAILS_ENV production
# ENV RAILS_SERVE_STATIC_FILES true
# RUN bundle exec rake DATABASE_URL=postgresql:does_not_exist assets:precompile

CMD ["rails", "server", "-b", "0.0.0.0"]
>>>>>>> Draft create
