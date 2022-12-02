package general_utils

import "github.com/lukaspastva/source-code/cli/utils/script_utils"

func VMSetup() {
	sh("mkdir -p .general-training-extra")
	sh("git clone https://github.com/cykerway/complete-alias .general-training-extra/complete-alias")
	file(".bashrc.general-training", `# general-training bashrc
. ~/.general-training-extra/complete-alias/complete_alias

source <(slu completion bash)
source <(training-cli completion bash)

alias w="watch -n 0.3"
`)
	sh(`echo ". ~/.bashrc.general-training\n" >> .bashrc`)
}

// utils

func sh(script string) {
	script_utils.Sh(script)
}

func file(file_path, content string) {
	script_utils.File(file_path, content)
}
