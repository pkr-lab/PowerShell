### Installation

git clone <URL> /opt/git/mein-projekt
install -m 0755 git-pull-deploy.sh /usr/local/bin/git-pull-deploy.sh
git-pull-deploy.sh --check


### Taegliche lauf
crontab -e 
0 4 * * * /usr/local/bin/git-pull-deploy.sh >> /var/log/git-pull-deploy.log 2>&1
