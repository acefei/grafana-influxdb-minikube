#!/bin/bash

CWD=$(cd $(dirname “${BASH_SOURCE:-$0}”) && pwd)

_setup_docker() {
    # setup docker as minikube's drive
    which docker > /dev/null && return
    curl -fsSL https://get.docker.com/ | sh
    sudo usermod -aG docker $USER
    echo "please re-login and run $0 again"
    exit
}

_setup_minikube() {
    _setup_docker
    which minikube > /dev/null && return
    curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
    sudo mv minikube-linux-amd64 /usr/local/bin/minikube
}

check_nginx_controller_running() {
    if kubectl get pods -n ingress-nginx | grep controller | grep Running; then
        true
    else
        false
    fi
}

_minikube_start() {
    _setup_minikube
    minikube ip > /dev/null || minikube start

    if ! check_nginx_controller_running; then
        minikube addons enable ingress
        # wait ingress boot up completely
        sleep 60
        if ! check_nginx_controller_running; then
            echo "Nginx controller is not up"
            exit 1
        fi
     fi
}

_setup_kubectl() {
    which kubectl > /dev/null && return
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    sudo mv kubectl /usr/local/bin/kubectl
    echo 'source <(kubectl completion bash)' >> ~/.bash_profile
}

_setup_k9s() {
    which k9s > /dev/null && return
    echo "alias k9sd='docker pull quay.io/derailed/k9s && docker run --rm -it -v $KUBECONFIG:/root/.kube/config quay.io/derailed/k9s'" >> ~/.bash_profile
}

_deploy_start() {
    kubectl apply -R -f .
}


myip () {
    ip a s $(ip r | head -1 | sed -n '/^default/s/.*\(dev [^ ]*\).*/\1/p') | sed -n '/inet/s/.*inet \([^\/]*\).*/\1/p'
}

#  the way to access minikube from external host, either nginx or kubectl port-forward
_setup_nginx() {
    # Deploying Nginx reverse proxy in front of minikube.
    _minikube_start
    sudo systemctl status nginx || sudo apt install nginx -y

	cat <<EOF > /etc/nginx/conf.d/minikube.conf 
server {
    listen       80;
    server_name  `myip`;
    location / {   
        proxy_pass http://`minikube ip`;
        proxy_set_header Host \$host;
    }
}
EOF
    sudo systemctl restart nginx
}

_expose_ingress_controller() {
    # expose ingress on minikube to external hosts
    kubectl port-forward --address 0.0.0.0 deployment/ingress-nginx-controller 8443:443 --namespace ingress-nginx
    printf "\n---> now the ingress can be reached from other hosts by\nhttps://`myip`:8443/\n"
}

install_functions() {
    grep -Po "^_[\w-]+(?=\(\))" $0
}

main() {
    local func_list=$(install_functions)
    local func
    for func in $func_list; do
		echo "---> start $func..."
		${func}
		echo "---> $func done..."
    done
}

if [ -z "${1:-}" ];then
    main
else
    eval "_$1"
fi
