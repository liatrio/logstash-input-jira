pipeline {
  agent {
    label "logstash"
  }
  environment {
    ORG = 'liatrio'
    APP_NAME = 'logstash-input-jira'
    //CHARTMUSEUM_CREDS = credentials('jenkins-x-chartmuseum')
    DOCKER_REGISTRY = 'docker.artifactory.liatr.io'
    SLACK_CHANNEL="flywheel"
  }
  stages {
    stage('Build image') {
      steps {
        container('logstash') {
          sh "docker build -t ${DOCKER_REGISTRY}/${ORG}/${APP_NAME}:${GIT_COMMIT[0..10]} -t ${DOCKER_REGISTRY}/${ORG}/${APP_NAME}:latest ."
        }
      }
    }
    stage('Publish image') {
     // when {
       // branch 'master'
     // }
      steps {
        container('logstash') {
          script {
          docker.withRegistry("https://${DOCKER_REGISTRY}", 'artifactory-takumin') {
            sh "docker push ${DOCKER_REGISTRY}/${ORG}/${APP_NAME}:${GIT_COMMIT[0..10]}"
            sh "docker push ${DOCKER_REGISTRY}/${ORG}/${APP_NAME}:latest"
          }
          }
        }
      }
    }
    //NEED to figure out how to grab latest chart version.
    stage('Deploy new Image') {
      agent { label 'jenkins-maven-java11' }
      steps {
        container('maven') {
          withCredentials([usernamePassword(credentialsId: 'artifactory-takumin', variable: 'CREDS', usernameVariable: 'USERNAME', passwordVariable: 'PASSWORD')]) {
            sh """
              helm init --client-only
              helm repo add liatrio-artifactory "https://artifactory.liatr.io/artifactory/helm" --username $USERNAME --password $PASSWORD
              helm repo update
              helm upgrade lead-dashboard liatrio-artifactory/lead-dashboard --namespace toolchain --set logstash-jira.image.tag=${GIT_COMMIT[0..10]}
              """
       }
        }
      }
    }
  }
  /*post {
    failure {
      slackSend channel: "#${env.SLACK_CHANNEL}",  color: "danger", message: "Build failed: ${env.JOB_NAME} on build #${env.BUILD_NUMBER} (<${env.BUILD_URL}|go there>)"
    }
    fixed {
      slackSend channel: "#${env.SLACK_CHANNEL}", color: "good",  message: "Build recovered: ${env.JOB_NAME} on #${env.BUILD_NUMBER}"
    }
    success {
      slackSend channel: "#${env.SLACK_CHANNEL}", color: "good",  message: "Build was successfully deployed: ${env.JOB_NAME} on #${env.BUILD_NUMBER} (<${env.BUILD_URL}|go there>)"
    }
  } */
}
