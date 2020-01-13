package main_test

import (
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"testing"

	. "github.com/cloudfoundry/buildpacks-ci/tasks/update-dotnet-compatibility-table"
	"github.com/mitchellh/mapstructure"

	"github.com/BurntSushi/toml"
	"github.com/sclevine/spec"
	"github.com/sclevine/spec/report"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

var update = flag.Bool("update", false, "updates golden files")

func TestUpdateCNBDependencyTask(t *testing.T) {
	spec.Run(t, "UpdateCNBDependencyTask", testUpdateCNBDependencyTask, spec.Report(report.Terminal{}))
}

func testUpdateCNBDependencyTask(t *testing.T, when spec.G, it spec.S) {
	var (
		testdataPath = "testdata"
		envVars      = []string{
			"HOME=" + os.Getenv("HOME"),
			"PATH=" + os.Getenv("PATH"),
		}
		outputDir string
	)
	when("with empty buildpack.toml", func() {
		it("add version of sdk dependency", func() {
			outputDir = filepath.Join(testdataPath, "artifacts")
			require.NoError(t, os.RemoveAll(outputDir))
			require.NoError(t, os.Mkdir(outputDir, 0755))
			require.NoError(t, exec.Command("git", "-C", outputDir, "init").Run())

			taskCmd := exec.Command(
				"go", "run", "github.com/cloudfoundry/buildpacks-ci/tasks/update-dotnet-compatibility-table",
				"--buildpack-toml", "",
				"--sdk-version", "2.1.102",
				"--output-dir", outputDir,
				"--runtime-version", "2.1.1",
			)
			taskCmd.Env = append(taskCmd.Env, envVars...)

			taskOutput, err := taskCmd.CombinedOutput()
			require.NoError(t, err, string(taskOutput))
			fmt.Println(string(taskOutput))

			outputBuildpackToml := decodeBuildpackTOML(t, outputDir)

			var compatibilityTable RuntimeToSDKs
			require.NoError(t, mapstructure.Decode(outputBuildpackToml.Metadata["runtime-to-sdks"], &compatibilityTable))

			// assert.Equal(t, RuntimeToSDKs{
			// 	{
			// 		RuntimeVersion: "2.1.1",
			// 		SDKs:           []string{"2.1.102"},
			// 	},
			// }, compatibilityTable)

		})
	})

	when("with runtime version doesn't exist in buildpack.toml", func() {
		it("add version of sdk dependency", func() {
			outputDir = filepath.Join(testdataPath, "artifacts")
			require.NoError(t, os.RemoveAll(outputDir))
			require.NoError(t, os.Mkdir(outputDir, 0755))
			require.NoError(t, exec.Command("git", "-C", outputDir, "init").Run())

			buildpackTOMLContents := `
  [[metadata.runtime-to-sdks]]
    runtime-version = "2.1.12"
    sdks = ["2.1.801", "2.1.701", "2.1.605", "2.1.508"]`

			taskCmd := exec.Command(
				"go", "run", "github.com/cloudfoundry/buildpacks-ci/tasks/update-dotnet-compatibility-table",
				"--buildpack-toml", buildpackTOMLContents,
				"--sdk-version", "2.1.802",
				"--output-dir", outputDir,
				"--runtime-version", "2.1.13",
			)
			taskCmd.Env = append(taskCmd.Env, envVars...)

			taskOutput, err := taskCmd.CombinedOutput()
			require.NoError(t, err, string(taskOutput))
			fmt.Println(string(taskOutput))

			outputBuildpackToml := decodeBuildpackTOML(t, outputDir)

			var compatibilityTable RuntimeToSDKs
			require.NoError(t, mapstructure.Decode(outputBuildpackToml.Metadata["runtime-to-sdks"], &compatibilityTable))

			// assert.Equal(t, RuntimeToSDKs{
			// 	{
			// 		RuntimeVersion: "2.1.12",
			// 		SDKs:           []string{"2.1.801", "2.1.701", "2.1.605", "2.1.508"},
			// 	},
			// 	{
			// 		RuntimeVersion: "2.1.13",
			// 		SDKs:           []string{"2.1.802"},
			// 	},
			// }, compatibilityTable)
			//
		})
	})

	when("with runtime version present in buildpack.toml", func() {
		it.Focus("add version of sdk dependency to list in sorted way", func() {
			outputDir = filepath.Join(testdataPath, "artifacts")
			require.NoError(t, os.RemoveAll(outputDir))
			require.NoError(t, os.Mkdir(outputDir, 0755))
			require.NoError(t, exec.Command("git", "-C", outputDir, "init").Run())

			buildpackTOMLContents := `
  [[metadata.runtime-to-sdks]]
    runtime-version = "1.1.13"
    sdks = ["1.1.801", "1.1.701", "1.1.605", "1.1.508"]
	[[metadata.runtime-to-sdks]]
    runtime-version = "2.1.13"
    sdks = ["2.1.801", "2.1.701", "2.1.605", "2.1.508"]`

			taskCmd := exec.Command(
				"go", "run", "github.com/cloudfoundry/buildpacks-ci/tasks/update-dotnet-compatibility-table",
				"--buildpack-toml", buildpackTOMLContents,
				"--sdk-version", "2.1.606",
				"--output-dir", outputDir,
				"--runtime-version", "2.1.13",
			)
			taskCmd.Env = append(taskCmd.Env, envVars...)

			taskOutput, err := taskCmd.CombinedOutput()
			require.NoError(t, err, string(taskOutput))
			fmt.Println(string(taskOutput))

			outputBuildpackToml := decodeBuildpackTOML(t, outputDir)

			fmt.Printf("[DEBUG] %v\n", outputBuildpackToml)
			var compatibilityTable []struct {
				RuntimeVersion string   `toml:"runtime-version" mapstructure:"runtime-version"`
				SDKs           []string `toml:"sdks" mapstructure:"sdks"`
			}

			require.NoError(t, mapstructure.Decode(outputBuildpackToml.Metadata["runtime-to-sdks"], &compatibilityTable))

			fmt.Printf("[DEBUG] %#v\n", compatibilityTable)

			assert.Equal(t, map[string]interface{}{
				"metadata.runtime-to-sdks": map[string]interface{}{
					"1.1.13": []interface{}{
						"1.1.801", "1.1.701", "1.1.605", "1.1.508",
					},
					"2.1.13": []interface{}{
						"2.1.801", "2.1.701", "2.1.605", "2.1.508",
					},
				},
			}, compatibilityTable)

			// assert.Equal(t, RuntimeToSDKs{
			// 	{
			// 		RuntimeVersion: "1.1.13",
			// 		SDKs:           []string{"1.1.801", "1.1.701", "1.1.605", "1.1.508"},
			// 		SDKs: []semver.Version{
			// 			{Major: 1, Minor: 1, Patch: 801},
			// 			{Major: 1, Minor: 1, Patch: 701},
			// 			{Major: 1, Minor: 1, Patch: 605},
			// 			{Major: 1, Minor: 1, Patch: 605},
			// 		},
			// 	},
			// 	{
			// 		RuntimeVersion: "2.1.13",
			// 		SDKs:           []string{"2.1.606", "2.1.801", "2.1.701", "2.1.605", "2.1.508"},
			// 	},
			// }, compatibilityTable)

		})
	})
}

func decodeBuildpackTOML(t *testing.T, outputDir string) BuildpackTOML {
	var buildpackTOML BuildpackTOML
	_, err := toml.DecodeFile(filepath.Join(outputDir, "buildpack.toml"), &buildpackTOML)
	require.NoError(t, err)
	return buildpackTOML
}
