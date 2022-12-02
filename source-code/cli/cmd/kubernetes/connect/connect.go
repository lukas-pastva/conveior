package connect

import (
	"encoding/base64"
	"errors"
	"fmt"
	"io"
	"io/ioutil"
	"log"
	"net/http"
	"os"
	"path"
	"time"

	parent_cmd "github.com/lukaspastva/source-code/cli/cmd/kubernetes"
	"github.com/sikalabs/slu/utils/file_utils"
	"github.com/spf13/cobra"
)

var Cmd = &cobra.Command{
	Use:     "connect",
	Short:   "Add my sikademo cluster",
	Aliases: []string{"c", "conn", "con", "add"},
	Args:    cobra.NoArgs,
	Run: func(c *cobra.Command, args []string) {
		home, err := os.UserHomeDir()
		if err != nil {
			log.Fatal(err)
		}
		t := time.Now()
		kubeDir := path.Join(home, ".kube")
		kubeConf := path.Join(kubeDir, "config")
		kubeConfSikademo := path.Join(kubeDir, "config.sikademo")
		kubeConfSikademoBase64 := kubeConfSikademo + ".base64"
		kubeConfBackup := path.Join(kubeDir, ".config."+t.Format("2006-01-02_15-04-05")+".backup")
		kubeConfOriginal := path.Join(kubeDir, "config.original")

		// ensure ~/.kube dir
		file_utils.EnsureDir(kubeDir)

		// backup only if ~/.kube/config exists
		if _, err := os.Stat(kubeConf); err == nil {
			// backup ~/.kube/config every time
			copyFile(kubeConf, kubeConfBackup)
			fmt.Println("Your original ~/.kube/config has been backed up to " + kubeConfBackup)

			// backup ~/.kube/config to ~/.kube/config.original only if config.original is not exists
			if _, err := os.Stat(kubeConfOriginal); errors.Is(err, os.ErrNotExist) {
				copyFile(kubeConf, kubeConfOriginal)
				fmt.Println("Your original ~/.kube/config has been copied to " + kubeConfOriginal)
			}
		}

		// download ~/.kube/config.sikademo
		downloadFile(kubeConfSikademoBase64, "https://raw.githubusercontent.com/ondrejsika/kubeconfig-sikademo/master/kubeconfig")
		base64Decode(kubeConfSikademoBase64, kubeConfSikademo)

		// copy ~/.kube/config.sikademo to ~/.kube/config
		copyFile(kubeConfSikademo, kubeConf)
		fmt.Println("You are connected to my demo cluster")
	},
}

func init() {
	parent_cmd.Cmd.AddCommand(Cmd)
}

// Utils

func copyFile(src, dest string) {
	bytesRead, err := ioutil.ReadFile(src)
	if err != nil {
		log.Fatal(err)
	}
	err = ioutil.WriteFile(dest, bytesRead, 0644)
	if err != nil {
		log.Fatal(err)
	}
}

func downloadFileRaw(path string, url string) error {
	// Get the data
	resp, err := http.Get(url)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	// Create the file
	out, err := os.Create(path)
	if err != nil {
		return err
	}
	defer out.Close()

	// Write the body to file
	_, err = io.Copy(out, resp.Body)
	return err
}

func downloadFile(path string, url string) {
	err := downloadFileRaw(path, url)
	if err != nil {
		log.Fatal(err)
	}
}

func base64Decode(src, dest string) {
	bytesRead, err := ioutil.ReadFile(src)
	if err != nil {
		log.Fatal(err)
	}
	decoded, err := base64.StdEncoding.DecodeString(string(bytesRead))
	if err != nil {
		log.Fatal(err)
	}
	err = ioutil.WriteFile(dest, []byte(decoded), 0644)
	if err != nil {
		log.Fatal(err)
	}
}
