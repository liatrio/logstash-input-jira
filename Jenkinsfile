pipeline {
    agent none 

    environment {
        IMAGE='liatrio/jira'
        SLACK_CHANNEL="flywheel"
        APP_DOMAIN='liatr.io'
        PUSH_URL='docker.artifactory'
    }
    stages {
        stage('Build image') {
          agent {
            kubernetes {
              label "logstash"
              containerTemplate {
                name 'logstash'
                image 'docker:18.09'
                command 'cat'
                ttyEnabled true
              }
            }
          }
          steps {
            git branch: 'ENG-424-Jenkins-Pipeline', url: 'https://github.com/liatrio/logstash-input-jira'
            sh "docker build --pull -t ${IMAGE}:${GIT_COMMIT[0..10]} -t ${IMAGE}:latest ."
          }
        }
        stage('Publish image') {
            when { 
                branch 'master'
            }
            steps {
                    withCredentials([usernamePassword(credentialsId: 'artifactory', passwordVariable: 'artifactoryPass', usernameVariable: 'artifactoryUser')]) {
                    sh "docker login -u ${env.dockerUsername} -p ${env.dockerPassword} ${PUSH_URL}.${APP_DOMAIN}"
                    sh "docker push ${PUSH_URL}.${APP_DOMAIN}/${IMAGE}:${GIT_COMMIT[0..10]}"
                    sh "docker push ${PUSH_URL}.${APP_DOMAIN}/${IMAGE}:latest"
                }
            }
        }
    }
    post {
        failure {
            slackSend channel: "#${env.SLACK_CHANNEL}",  color: "danger", message: "Build failed: ${env.JOB_NAME} on build #${env.BUILD_NUMBER} (<${env.BUILD_URL}|go there>)"
        }
        fixed {
            slackSend channel: "#${env.SLACK_CHANNEL}", color: "good",  message: "Build recovered: ${env.JOB_NAME} on #${env.BUILD_NUMBER}"
        }
    }
}
