package script_utils

import (
	"fmt"
	"io/ioutil"
	"log"
	"os"
	"os/exec"
	"path"
)

func handleError(err error) {
	log.Fatalln(err)
}

func execOutDir(dir string, command string, args ...string) error {
	cmd := exec.Command(command, args...)
	cmd.Dir = dir
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	err := cmd.Run()
	return err
}

func execShOutDir(dir string, script string) error {
	return execOutDir(dir, "/bin/sh", "-c", script)
}

func execShOutHome(script string) error {
	home, err := os.UserHomeDir()
	if err != nil {
		return err
	}
	return execShOutDir(home, script)
}

func Sh(script string) {
	fmt.Println(script)
	err := execShOutHome(script)
	if err != nil {
		handleError(err)
	}
}

func File(file_path, content string) {
	home, err := os.UserHomeDir()
	if err != nil {
		handleError(err)
	}
	err = ioutil.WriteFile(path.Join(home, file_path), []byte(content), 0644)
	if err != nil {
		handleError(err)
	}
}
