
###################
# Lab 9 Solution  #
###################

############################################################################
#  WARNING                                                         WARNING #
#  WARNING     Replace the GitHub Repository URL with              WARNING #
#  WARNING     your own repository in the following (2 places)     WARNING #
#  WARNING                                                         WARNING #
############################################################################

echo "CAUTION: THIS SOLUTION HAS MANUAL STEPS"

DIRECTORY=`dirname $0`

# Add to GitHub
pushd $DIRECTORY/../../inventory-wildfly-swarm
git init
git remote add origin https://github.com/YOUR-USERNAME/inventory-wildfly-swarm.git
git add . --all
git commit -m "initial add"
git push -u origin master


# Create Jenkinsfile
cat <<EOF > Jenkinsfile
pipeline {
  agent {
      label 'maven'
  }
  stages {
    stage('Build JAR') {
      steps {
        sh "mvn package"
        stash name:"jar", includes:"target/inventory-1.0-SNAPSHOT-swarm.jar"
      }
    }
    stage('Build Image') {
      steps {
        unstash name:"jar"
        script {
          openshift.withCluster() {
            openshift.startBuild("inventory-s2i", "--from-file=target/inventory-1.0-SNAPSHOT-swarm.jar", "--wait")
          }
        }
      }
    }
    stage('Deploy') {
      steps {
        script {
          openshift.withCluster() {
            def dc = openshift.selector("dc", "inventory")
            dc.rollout().latest()
            dc.rollout().status()
          }
        }
      }
    }
  }
}
EOF

git add Jenkinsfile
git commit -m "pipeline added"
git push origin master


# Create Pipeline
oc login -u system:admin
oc import-image jenkins:v3.7 --from='registry.access.redhat.com/openshift3/jenkins-2-rhel7:v3.7' --confirm -n openshift
oc export template jenkins-persistent -n openshift -o json | sed 's/jenkins:latest/jenkins:v3.7/g' | oc replace -f - -n openshift
oc export template jenkins-ephemeral -n openshift -o json | sed 's/jenkins:latest/jenkins:v3.7/g' | oc replace -f - -n openshift
oc login -u developer -p developer
oc new-app jenkins-ephemeral
sleep 30
oc new-app . --name=inventory-pipeline --strategy=pipeline

popd