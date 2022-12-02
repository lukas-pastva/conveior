package terraform_utils

import "github.com/lukaspastva/source-code/cli/utils/script_utils"

func VMSetup() {
	sh("mkdir -p .terraform-training-bin")
	sh("slu install-bin-tool --bin-dir .terraform-training-bin terraform")
	sh("git clone https://github.com/cykerway/complete-alias .terraform-training-extra/complete-alias")
	file(".bashrc.terraform-training", `# terraform-training bashrc
. ~/.terraform-training-extra/complete-alias/complete_alias

export PATH="$PATH":$HOME/.terraform-training-bin

# terraform
alias tf=terraform
complete -F _complete_alias tf

alias w="watch -n 0.3"
`)
	sh(`echo ". ~/.bashrc.terraform-training\n" >> .bashrc`)
}

// utils

func sh(script string) {
	script_utils.Sh(script)
}

func file(file_path, content string) {
	script_utils.File(file_path, content)
}
