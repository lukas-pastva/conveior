package prometheus_utils

import "github.com/lukaspastva/source-code/cli/utils/script_utils"

func VMSetup() {
	sh("mkdir -p .prometheus-training-bin")
	sh("slu install-bin --bin-dir .prometheus-training-bin prometheus")
	sh("slu install-bin --bin-dir .prometheus-training-bin alertmanager")
	sh("slu install-bin --bin-dir .prometheus-training-bin amtool")
	sh("slu install-bin --bin-dir .prometheus-training-bin thanos")

	file(".bashrc.prometheus-training", `# prometheus-training bashrc
export PATH="$PATH":$HOME/.prometheus-training-bin

source <(slu completion bash)
source <(training-cli completion bash)

alias w="watch -n 0.3"
`)
	sh(`echo ". ~/.bashrc.prometheus-training\n" >> .bashrc`)
}

// utils

func sh(script string) {
	script_utils.Sh(script)
}

func file(file_path, content string) {
	script_utils.File(file_path, content)
}
