package kubernetes_utils

import "github.com/lukaspastva/source-code/cli/utils/script_utils"

func VMSetup() {
	sh("mkdir -p .kubernetes-training-bin")
	sh("slu install-bin-tool --bin-dir .kubernetes-training-bin helm")
	sh("slu install-bin-tool --bin-dir .kubernetes-training-bin kubectl")
	sh("slu install-bin-tool --bin-dir .kubernetes-training-bin minikube")
	sh("slu install-bin-tool --bin-dir .kubernetes-training-bin skaffold")
	sh("slu install-bin-tool --bin-dir .kubernetes-training-bin krew")
	sh(".kubernetes-training-bin/krew install krew")
	sh(".kubernetes-training-bin/krew install tree")
	sh(".kubernetes-training-bin/krew install lineage")
	sh("git clone https://github.com/jonmosco/kube-ps1 .kubernetes-training-extra/kube-ps1")
	sh("git clone https://github.com/ahmetb/kubectx .kubernetes-training-extra/kubectx")

	file(".bashrc.kubernetes-training", `# kubernetes-training bashrc
. ~/.kubernetes-training-extra/kube-ps1/kube-ps1.sh
export KUBE_PS1_SYMBOL_ENABLE=false
export PS1='$(kube_ps1)'$PS1

export PATH="$PATH":$HOME/.kubernetes-training-bin
export PATH="$PATH":$HOME/.kubernetes-training-extra/kubectx
export PATH="$PATH:$HOME/.krew/bin"

source <(kubectl completion bash)
source <(helm completion bash)
source <(minikube completion bash)

source <(slu completion bash)
source <(training-cli completion bash)

# kubectl
alias k=kubectl
complete -F _complete_alias k

# kubectx
alias kx=kubectx
complete -F _complete_alias kx

# kubens
alias kn=kubens
complete -F _complete_alias kn

# Other Kubernetes related aliases

alias kdev="kubectl run dev-$(date +%s) --rm -ti --image sikalabs/dev -- bash"

alias w="watch -n 0.3"
`)
	sh(`echo ". ~/.bashrc.kubernetes-training\n" >> .bashrc`)

}

// utils

func sh(script string) {
	script_utils.Sh(script)
}

func file(file_path, content string) {
	script_utils.File(file_path, content)
}
