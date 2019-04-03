pipeline {
  agent {
    label "logstash"
  }

  environment {
    ORG = 'liatrio'
    APP_NAME = 'logstash-input-jira'
    CHARTMUSEUM_CREDS = credentials('jenkins-x-chartmuseum')

    SLACK_CHANNEL="flywheel"
  }
  stages {
    stage('Build image') {
      steps {
        container('logstash') {
          sh "docker build -t $DOCKER_REGISTRY/$ORG/$APP_NAME:${GIT_COMMIT[0..10]} -t $DOCKER_REGISTRY/$ORG/$APP_NAME}:latest ."
        }
      }
    }
    stage('Publish image') {
      when {
        branch 'master'
      }
      steps {
        container('logstash') {
          sh "docker push $DOCKER_REGISTRY/$ORG/$APP_NAME:${GIT_COMMIT[0..10]}"
          sh "docker push $DOCKER_REGISTRY/$ORG/$APP_NAME:latest"
        }
      }
    }
  }
  /* post {
  failure {
  slackSend channel: "#${env.SLACK_CHANNEL}",  color: "danger", message: "Build failed: ${env.JOB_NAME} on build #${env.BUILD_NUMBER} (<${env.BUILD_URL}|go there>)"
}
fixed {
slackSend channel: "#${env.SLACK_CHANNEL}", color: "good",  message: "Build recovered: ${env.JOB_NAME} on #${env.BUILD_NUMBER}"
}
} */
}
