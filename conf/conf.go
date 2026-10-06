// Copyright 2025 The contributors of Goinfer.
// This file is part of Goinfer, a LLM proxy under the MIT License.
// SPDX-License-Identifier: MIT

package conf

import (
	"errors"
	"io/fs"
	"log/slog"
	"net"
	"os"
	"slices"
	"strings"
	"syscall"

	"github.com/goccy/go-yaml"

	"github.com/lynxai-team/garcon/gerr"

	"github.com/lynxai-team/goinfer/proxy/config"
)

type (
	// Cfg holds all settings.
	Cfg struct {
		ExtraModels    map[string]string     `json:"extra_models,omitempty"  toml:"extra_models" yaml:"extra_models" env:"GI_EXTRA_MODELS" comment:"Download models using llama-server flags - GI_EXTRA_MODELS\nsee : github.com/ggml-org/llama.cpp/blob/master/common/arg.cpp#L3000"`
		Info           map[string]*ModelInfo `json:"info,omitempty"  toml:"-" yaml:"-"`
		Swap           *config.Config        `json:"swap,omitempty"  toml:"-" yaml:"-"`
		Llama          Llama                 `json:"llama,omitzero"  toml:"llama" yaml:"llama"`
		APIKey         string                `json:"api_key,omitempty"  toml:"api_key" yaml:"api_key" env:"GI_API_KEY" comment:"⚠️ Set your API key, can be 64-hex-digit (32-byte) 🚨\nGoinfer sets a random API key with: ./goinfer -overwrite-all"`
		Host           string                `json:"host,omitempty"  toml:"host,omitempty" yaml:"host,omitempty" env:"GI_HOST" comment:"\nHost to listen - GI_HOST"`
		Origins        string                `json:"origins,omitempty"  toml:"origins" yaml:"origins" env:"GI_ORIGINS" comment:"\nCORS whitelist - GI_ORIGINS"`
		ModelsDir      string                `json:"models_dir,omitempty"  toml:"models_dir" yaml:"models_dir" env:"GI_MODELS_DIR" comment:"\nGoinfer recursively searches GGUF files in one or multiple folders separated by ':'\nList your GGUF dirs with: locate .gguf | sed -e 's,/[^/]*$,,' | uniq\nenv. var: GI_MODELS_DIR"`
		DefaultModel   string                `json:"default_model,omitempty"  toml:"default_model" yaml:"default_model" env:"GI_DEFAULT_MODEL" comment:"\nThe default model name to load at startup - GI_DEFAULT_MODEL\nCan also be set with: ./goinfer -start <model-name>"`
		ListenAddr     string                `json:"listen_addr,omitempty"  toml:"listen_addr" yaml:"listen_addr" env:"GI_LISTEN_ADDR" comment:"address can be 'ip:port' or 'host:port' or ':port' (default host is localhost) - GI_LISTEN_ADDR"`
		Endpoints      []string              `json:"endpoints,omitempty"  toml:"endpoints" yaml:"endpoints" env:"GI_ENDPOINTS,required,separator=;" comment:"Semicolon-separated list of http(s):// URLs to connect to one or more Goinfer-proxies"`
		TrustedSubnets []string              `json:"trusted_subnets,omitempty"  toml:"trusted_subnets,omitempty" yaml:"trusted_subnets,omitempty" env:"GI_TRUSTED_SUBNETS,separator=," comment:"\nComma-separated CIDR blocks for X-Forwarded-For validation - GI_TRUSTED_SUBNETS"`
		TLS            bool                  `json:"tls,omitempty"  toml:"tls" yaml:"tls" env:"GI_TLS" envDefault:"true" comment:"\nSet to false to serve clear-text HTTP/2 (h2c) and disable HTTP/3 - GI_TLS"`
		ACMEEmail      string                `json:"acme_email,omitempty"  toml:"acme_email" yaml:"acme_email" env:"GI_ACME_EMAIL" comment:"\nE-mail address for ACME certificate issuance - GI_ACME_EMAIL"`
		ACMEDir        string                `json:"acme_dir,omitempty"    toml:"acme_dir"   yaml:"acme_dir" env:"GI_ACME_DIR" envDefault:"/certs" comment:"\nDirectory used by autocert for caching certificates (must be writable) - GI_ACME_DIR"`
		LogLevel       string                `json:"log_level,omitempty"   toml:"log_level" yaml:"log_level" env:"GI_LOG_LEVEL" envDefault:"info" comment:"address can be 'host:port' or 'ip:por' or simply ':port' (for host = localhost)"`
	}

	// Llama holds the inference engine settings.
	Llama struct {
		Exe     string `toml:"exe"     yaml:"exe"     comment:"path of llama-server"`
		Common  string `toml:"common"  yaml:"common"  comment:"common args used for every model"`
		Smith   string `toml:"smith"   yaml:"smith"   comment:"extra args to let tools like Agent-Smith doing the templating (/completions endpoint)"`
		Verbose string `toml:"verbose" yaml:"verbose" comment:"extra llama-server flag when ./goinfer is used without the -q flag"`
		Debug   string `toml:"debug"   yaml:"debug"   comment:"extra llama-server flag for ./goinfer -debug"`
	}
)

const (
	// Sentence: Coffee is cool, so coffee is good. Bad code is dead, lol. Cafe gift, go cafe, test code.
	// Hex code: C0ffee 15 C001, 50 C0ffee 15 900d. Bad C0de 15 Dead, 101. Cafe 91f7, 90 Cafe, 7e57 C0de.
	debugAPIKey   = "C0ffee15C00150C0ffee15900dBadC0de15Dead101Cafe91f790Cafe7e57C0de"
	unsetAPIKey   = "Please ⚠️ Set your private 64-hex-digit API key (32 bytes)"
	TemplateJinja = "template.jinja"
)

// Do not use the bad ports: they are blocked by web browsers,
// as specified by the Fetch standard: fetch.spec.whatwg.org/#port-blocking.
var badPorts = []string{
	"0", "1", "7", "9", "11", "13", "15", "17", "19", "20", "21", "22", "23", "25",
	"37", "42", "43", "53", "69", "77", "79", "87", "95", "101", "102", "103", "104",
	"109", "110", "111", "113", "115", "117", "119", "123", "135", "137", "139", "143",
	"161", "179", "389", "427", "465", "512", "513", "514", "515", "526", "530", "531",
	"532", "540", "548", "554", "556", "563", "587", "601", "636", "989", "990", "993",
	"995", "1719", "1720", "1723", "2049", "3659", "4045", "4190", "5060", "5061",
	"6000", "6566", "6665", "6666", "6667", "6668", "6669", "6679", "6697", "10080",
}

// DefaultCfg returns a unique copy of its local variable
// to each receiver preventing data race (concurrency testing).
func DefaultCfg() *Cfg {
	return &Cfg{
		ModelsDir:    "/home/me/path/to/models",
		DefaultModel: "",
		APIKey:       "",
		Host:         "",
		Origins:      "localhost",
		ListenAddr:   ":8080",
		Llama: Llama{
			Exe:     "/home/me/llama.cpp/build/bin/llama-server",
			Verbose: "",
			Debug:   "--log-verbosity 4",
			Common: `--load-mode none --prio 2 --prio-batch 2 --cpu-strict 1 --props --no-warmup ` +
				`--chat-template-kwargs '{"reasoning_effort":"max"}' ` +
				`--webui-config '{"showAgenticTurnStats":true,"showBuildVersion":true,"showMessageStats":true,"showSystemMessage":true,"alwaysShowToolCallContent":true,"pasteLongTextToFileLen":5555,"disableAutoScroll":false,"renderUserContentAsMarkdown":true}'`,
			// --webui-config defaults: https://github.com/ggml-org/llama.cpp/blob/master/tools/ui/src/lib/constants/settings-keys.constants.ts
			Smith: "--jinja --chat-template-file " + TemplateJinja,
		},
		// ExtraModels: map[string]string{ // Output of `llama-server -h` contains:
		// 	// github.com/ggml-org/llama.cpp/blob/master/common/arg.cpp#L3000
		// 	"OuteAI/OuteTTS-0.2-500M-GGUF+ggml-org/WavTokenizer": "--tts-oute-default",
		// 	"ggml-org/embeddinggemma-300M-qat-q4_0-GGUF":         "--embd-gemma-default",
		// 	"ggml-org/Qwen2.5-Coder-1.5B-Q8_0-GGUF":              "--fim-qwen-1.5b-default",
		// 	"ggml-org/Qwen2.5-Coder-3B-Q8_0-GGUF":                "--fim-qwen-3b-default",
		// 	"ggml-org/Qwen2.5-Coder-7B-Q8_0-GGUF":                "--fim-qwen-7b-default",
		// 	"ggml-org/Qwen2.5-Coder-7B-Q8_0-GGUF+0.5B-draft":     "--fim-qwen-7b-spec",
		// 	"ggml-org/Qwen2.5-Coder-14B-Q8_0-GGUF+0.5B-draft":    "--fim-qwen-14b-spec",
		// 	"ggml-org/Qwen3-Coder-30B-A3B-Instruct-Q8_0-GGUF":    "--fim-qwen-30b-default",
		// 	"ggml-org/gpt-oss-20b-GGUF":                          "--gpt-oss-20b-default",
		// 	"ggml-org/gpt-oss-120b-GGUF":                         "--gpt-oss-120b-default",
		// 	"ggml-org/gemma-3-4b-it-qat-GGUF":                    "--vision-gemma-4b-default",
		// 	"ggml-org/gemma-3-12b-it-qat-GGUF":                   "--vision-gemma-12b-default",
		// },
	}
}

// Print configuration.
func (cfg *Cfg) Print() {
	slog.Info("-------------------------------------------")

	printEnvVar("GI_MODELS_DIR", false)
	printEnvVar("GI_EXTRA_MODELS", false)
	printEnvVar("GI_DEFAULT_MODEL", false)
	printEnvVar("GI_HOST", false)
	printEnvVar("GI_ORIGINS", false)
	printEnvVar("GI_API_KEY", true)
	printEnvVar("GI_LLAMA_EXE", false)

	slog.Info("-------------------------------------------")

	yml, err := yaml.Marshal(&cfg)
	if err != nil {
		slog.Error("Failed yaml.Marshal", "err", err, "input struct", &cfg)
		return
	}

	_, err = os.Stdout.Write(yml)
	if err != nil {
		slog.Error("Failed Write(yml)", "err", err, "content", string(yml[:200]))
	}

	slog.Info("-------------------------------------------")
}

func printEnvVar(key string, confidential bool) {
	v, set := syscall.Getenv(key)
	switch {
	case !set:
		slog.Info("env", key, "(unset)")
	case v == "":
		slog.Info("env", key, "(empty)")
	case confidential:
		slog.Info("env", key+"-length", len(v))
	default:
		slog.Info("env", key, v)
	}
}

func (cfg *Cfg) validate(noAPIKey bool) error {
	err := cfg.validateAddr()
	if err != nil {
		return err
	}

	// GI_MODELS_DIR
	for dir := range strings.SplitSeq(cfg.ModelsDir, ":") {
		info, er := os.Stat(dir)
		if errors.Is(er, fs.ErrNotExist) {
			return gerr.New(gerr.ConfigErr, "Verify GI_MODELS_DIR or 'models_dir' in "+GoinferINI, "does not exist", dir)
		}
		if er != nil {
			return gerr.Wrap(er, gerr.ConfigErr, "Verify GI_MODELS_DIR or 'models_dir' in "+GoinferINI, "problem with", dir)
		}
		if !info.IsDir() {
			return gerr.New(gerr.ConfigErr, "Verify GI_MODELS_DIR or 'models_dir' in "+GoinferINI, "must be a directory", dir)
		}
	}

	// GI_LLAMA_EXE
	info, err := os.Stat(cfg.Llama.Exe)
	if errors.Is(err, fs.ErrNotExist) {
		return gerr.New(gerr.ConfigErr, "GI_LLAMA_EXE or 'exe' in goinfer.ini: file does not exist", "exe", cfg.Llama.Exe)
	}
	if err != nil {
		return gerr.Wrap(err, gerr.ConfigErr, "GI_MODELS_DIR or 'models_dir' in goinfer.ini", "exe", cfg.Llama.Exe)
	}
	if info.IsDir() {
		return gerr.New(gerr.ConfigErr, "GI_LLAMA_EXE or 'exe' in goinfer.ini: must be a file, not a directory", "exe", cfg.Llama.Exe)
	}

	// API key
	if noAPIKey {
		slog.Info("Flag -no-api-key => Do not verify API key.")
		return nil
	}
	if cfg.APIKey == "" || strings.Contains(cfg.APIKey, "Please") {
		return gerr.New(gerr.ConfigErr, "API key not set, please set your private API key")
	}
	if cfg.APIKey == debugAPIKey {
		slog.Warn("API key is DEBUG => security threat")
	} else if len(cfg.APIKey) < 64 {
		slog.Warn("API key should be 64+ hex digits", "len", len(cfg.APIKey))
	}
	return nil
}

// validateAddr() prevents bad ports: they are blocked by web browsers,
// as specified by the Fetch standard: http://fetch.spec.whatwg.org/#bad-port
func (cfg *Cfg) validateAddr() error {
	_, port, err := net.SplitHostPort(cfg.ListenAddr)
	if err != nil {
		slog.Error("Cannot SplitHostPort", "cfg.Addr", cfg.ListenAddr, "err", err)
		return err
	}
	if slices.Contains(badPorts, port) {
		const msg = "Chrome/Firefox block the bad ports"
		slog.Error(msg, "port", port, "reference", "https://fetch.spec.whatwg.org/#port-blocking")
		return gerr.New(gerr.ConfigErr, msg, "port", port, "reference", "https://fetch.spec.whatwg.org/#port-blocking")
	}
	return nil
}
