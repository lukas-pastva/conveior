package rancher_utils

import "github.com/lukaspastva/source-code/cli/utils/script_utils"

func VMSetup() {
	sh("mkdir -p .rancher-training-bin")
	sh("slu install-bin-tool --bin-dir .rancher-training-bin rancher")

	file(".bashrc.rancher-training", `# rancher-training bashrc
export PATH="$PATH":$HOME/.rancher-training-bin
`)
	sh(`echo ". ~/.bashrc.rancher-training\n" >> .bashrc`)
}

// utils

func sh(script string) {
	script_utils.Sh(script)
}

func file(file_path, content string) {
	script_utils.File(file_path, content)
}
