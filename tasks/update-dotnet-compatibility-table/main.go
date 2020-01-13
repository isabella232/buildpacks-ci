package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"

	"github.com/BurntSushi/toml"
	"github.com/blang/semver"
	"github.com/mitchellh/mapstructure"
	"github.com/pkg/errors"
)

var flags struct {
	buildpackTOML  string
	runtimeVersion string
	outputDir      string
	sdkVersion     string
}

type BuildpackTOML struct {
	Metadata Metadata `toml:"metadata"`
}

type Metadata map[string]interface{}

type RuntimeToSDKs []RuntimeToSDK

type RuntimeToSDK struct {
	RuntimeVersion string           `toml:"runtime-version"`
	SDKs           []semver.Version `toml:"-"`
	DisplayValues  []string         `toml:"sdks"`
}

const RuntimeToSDKsKey = "runtime-to-sdks"

func main() {
	flag.StringVar(&flags.buildpackTOML, "buildpack-toml", "", "contents of buildpack.toml")
	flag.StringVar(&flags.runtimeVersion, "runtime-version", "", "runtime version")
	flag.StringVar(&flags.outputDir, "output-dir", "", "directory to write buildpack.toml to")
	flag.StringVar(&flags.sdkVersion, "sdk-version", "", "version of sdk")
	flag.Parse()

	buildpackTOML := BuildpackTOML{}

	if err := buildpackTOML.Load(flags.buildpackTOML); err != nil {
		fmt.Println("failed to load buildpack toml", err)
		os.Exit(1)
	}

	if err := buildpackTOML.AddSDKToRuntime(flags.sdkVersion, flags.runtimeVersion); err != nil {
		fmt.Println("failed to add sdk to runtime mapping", err)
		os.Exit(1)
	}

	fmt.Println(buildpackTOML)
	if err := buildpackTOML.WriteToFile(filepath.Join(flags.outputDir, "buildpack.toml")); err != nil {
		fmt.Println("failed to update buildpack toml", err)
		os.Exit(1)
	}
}

func (buildpackTOML *BuildpackTOML) Load(buildpackTOMLContents string) error {
	if _, err := toml.Decode(buildpackTOMLContents, &buildpackTOML); err != nil {
		return err
	}
	return nil
}

func (buildpackTOML *BuildpackTOML) AddSDKToRuntime(sdkVersion, runtimeVersion string) error {

	var inputs []struct {
		RuntimeVersion string   `toml:"runtime-version" mapstructure:"runtime-version"`
		SDKs           []string `toml:"sdks" mapstructure:"sdks"`
	}

	err := mapstructure.Decode(buildpackTOML.Metadata[RuntimeToSDKsKey], &inputs)
	if err != nil {
		return err
	}

	var existingRuntimeToSDKs RuntimeToSDKs

	for _, input := range inputs {
		var sdks []semver.Version

		for _, sdk := range input.SDKs {
			parsedSdk, _ := semver.Parse(sdk)
			sdks = append(sdks, parsedSdk)
		}

		existingRuntimeToSDKs = append(existingRuntimeToSDKs, RuntimeToSDK{
			RuntimeVersion: input.RuntimeVersion,
			SDKs:           sdks,
		})
	}

	parsedSdk, _ := semver.Parse(sdkVersion)

	runtimeExists := false
	for i, runtimeToSDK := range existingRuntimeToSDKs {
		if runtimeToSDK.RuntimeVersion == runtimeVersion {
			existingRuntimeToSDKs[i], _ = runtimeToSDK.addSdk(parsedSdk)
			runtimeExists = true
			break
		}
	}

	if !runtimeExists {
		existingRuntimeToSDKs = append(existingRuntimeToSDKs, RuntimeToSDK{
			RuntimeVersion: runtimeVersion,
			SDKs:           []semver.Version{parsedSdk},
		})
	}

	for i, runtimeSDK := range existingRuntimeToSDKs {
		var displayValues []string

		for _, j := range runtimeSDK.SDKs {
			displayValues = append(displayValues, j.String())
		}

		existingRuntimeToSDKs[i].DisplayValues = displayValues
	}

	buildpackTOML.Metadata = Metadata{RuntimeToSDKsKey: existingRuntimeToSDKs}
	return nil
}

func (runtimeToSDK RuntimeToSDK) addSdk(newSdk semver.Version) (RuntimeToSDK, error) {
	runtimeToSDK.SDKs = append(runtimeToSDK.SDKs, newSdk)
	semver.Sort(runtimeToSDK.SDKs)

	return runtimeToSDK, nil
}

func (buildpackTOML *BuildpackTOML) WriteToFile(filepath string) error {
	buildpackTOMLFile, err := os.Create(filepath)
	if err != nil {
		return errors.Wrap(err, fmt.Sprintf("failed to open buildpack.toml at: %s", filepath))
	}
	defer buildpackTOMLFile.Close()

	if err := toml.NewEncoder(buildpackTOMLFile).Encode(buildpackTOML); err != nil {
		return errors.Wrap(err, "failed to update the buildpack.toml")
	}
	return nil
}

// [[metadata.runtime-to-sdks]]
//   runtime-version = "2.1.12"
//   sdks = ["2.1.801", "2.1.701", "2.1.605", "2.1.508"]
//
// [[metadata.runtime-to-sdks]]
//   runtime-version = "2.1.13"
//   sdks = ["2.1.802", "2.1.606", "2.1.509"]
//
// [[metadata.runtime-to-sdks]]
//   runtime-version = "2.1.14"
//   sdks = ["2.1.607", "2.1.510"]
//
// [[metadata.runtime-to-sdks]]
//   runtime-version = "2.2.6"
//   sdks = ["2.2.401", "2.2.301", "2.2.205", "2.2.108"]
