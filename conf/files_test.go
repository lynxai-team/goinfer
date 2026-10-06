// Copyright 2025 The contributors of Goinfer.
// This file is part of Goinfer, a LLM proxy under the MIT License.
// SPDX-License-Identifier: MIT

package conf

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"testing/fstest"

	"github.com/lynxai-team/goinfer/proxy/config"
)

func Test_beautifyModelName(t *testing.T) {
	t.Parallel()
	tests := []struct{ in, want string }{
		{"30b/Devstral-Small-2507-GGUF_", "Devstral-Small-2507"},
		{"30b/Devstral-Small-2507-GGUF", "Devstral-Small-2507"},
		{"30b/Devstral-Small-2507_", "Devstral-Small-2507"},
		{"30b/Devstral-Small-2507-GGUF_Q8_K_XL", "Devstral-Small-2507:Q8_K_XL"},
		{"Devstral-Small-2507-GGUF_Q8_K_XL", "Devstral-Small-2507:Q8_K_XL"},
		{"folder/example-com_granite3.3_8b_Q4_K_M", "example-com/granite3.3_8b_Q4_K_M"},
		{"folder/example-eu_granite3.3_8b_Q4_K_M", "example-eu/granite3.3_8b_Q4_K_M"},
		{"folder/example-x_granite3.3_8b_Q4_K_M", "folder/example-x_granite3.3_8b_Q4_K_M"},
		{"folder/example-four_granite3.3_8b_Q4_K_M", "folder/example-four_granite3.3_8b_Q4_K_M"},
		{"folder/example-four/granite3.3_8b_Q4_K_M", "granite3.3_8b_Q4_K_M"},
		{"folder/example-com/granite3.3_8b_Q4_K_M", "example-com/granite3.3_8b_Q4_K_M"},
		{"folder/example-fr/granite3.3_8b_Q4_K_M", "example-fr/granite3.3_8b_Q4_K_M"},
		{"folder/example-o/granite3.3_8b_Q4_K_M", "granite3.3_8b_Q4_K_M"},
		{"folder/example/granite3.3_8b_Q4_K_M", "example/granite3.3_8b_Q4_K_M"},
		{"folder/granite3.3_8b_Q4_K_M", "folder/granite3.3_8b_Q4_K_M"},
		{"granite3.3_8b_Q4_K_M", "granite3.3_8b_Q4_K_M"},
		{"sub-directory/granite3.3_8b_Q4_K_M", "granite3.3_8b_Q4_K_M"},
		{"team-org_model_name", "team-org/model_name"},
		{"model_name", "model/name"},
		{"model-name", "model-name"},
		{"abcdefgh_fr_8", "abcdefgh/fr_8"},
		{"abcdefghi_fr_9", "abcdefghi/fr_9"},
		{"abcdefghij_fr_10", "abcdefghij_fr_10"},
		{"abcdefghijk_fr_11", "abcdefghijk_fr_11"},
		{"abcdefghijkl_fr_12", "abcdefghijkl_fr_12"},
		{"UI_WEB_name", "UI_WEB_name"},
		{"model1_2", "model1_2"},
		{"model-1-2", "model-1-2"},
		{"1234567890", "1234567890"},
		{"_llama-1", "_llama-1"},
		{"t_llama-1", "t_llama-1"},
		{"te_llama-1", "te_llama-1"},
		{"tea_llama-1", "tea_llama-1"},
		{"team_llama-1", "team/llama-1"},
		{"-_llama-1", "-_llama-1"},
		{"-abcd_llama-1", "-abcd_llama-1"},
		{"x-c_llama-1", "x-c_llama-1"},
		{"x-co_llama-1", "x-co_llama-1"},
		{"ab-fr_llama-1", "ab-fr_llama-1"},
		{"abc-fr_llama-1", "abc-fr_llama-1"},
		{"abcd-fr_llama-1", "abcd-fr/llama-1"},
		{"abcd-fr_llama-1", "abcd-fr/llama-1"},
		{"group/abcd-fr_llama-1", "abcd-fr/llama-1"},
		{"group/abcd-f_llama-1", "group/abcd-f_llama-1"},
		{"30b/abcd-f_llama-1", "abcd-f_llama-1"},
		{"mistral-ai/abcd-f_llama-1", "mistral-ai/abcd-f_llama-1"},
		{"mistral-ai/mistral-ai_llama-1", "mistral-ai/llama-1"},
		{"sub/rolex/granite3.3_8b_Q4_K_M", "rolex/granite3.3_8b_Q4_K_M"},
		{"rolex/granite3.3_8b_Q4_K_M", "rolex/granite3.3_8b_Q4_K_M"},
		{"granite3.3_8b_Q4_K_M", "granite3.3_8b_Q4_K_M"},
		{"ggml-org_gpt-oss-120b-GGUF_gpt-oss-120b-mxfp4", "ggml-org/gpt-oss-120b"},
		{"unsloth_Devstral-2-123B-Instruct-2512-GGUF_UD-Q4_K_XL_Devstral-2-123B-Instruct-2512-UD-Q4_K_XL", "unsloth/Devstral-2-123B-Instruct-2512:UD-Q4_K_XL"},
	}
	for _, tt := range tests {
		t.Run(tt.in, func(t *testing.T) {
			t.Parallel()
			const root = "/home/me/models"
			truncated := filepath.Join(root, tt.in)
			got := beautifyModelName("/home/me/models", truncated)
			if got != tt.want {
				t.Errorf("beautifyModelName(%q) = %q, want %q", truncated, got, tt.want)
			}
		})
	}
}

func Test_ExtractFlags_FromShell(t *testing.T) {
	t.Parallel()
	tmp := t.TempDir()

	// .sh file present
	modelPath := createGGUFFile(t, tmp, "model1.gguf", 2000)
	shPath := strings.TrimSuffix(modelPath, ".gguf") + ".sh"
	err := os.WriteFile(shPath, []byte("-foo bar -baz qux"), 0o600)
	if err != nil {
		t.Fatalf("failed to write .sh file: %v", err)
	}
	name, flags, origin := extractFlags(modelPath)
	if !strings.HasSuffix(name, "model1") {
		t.Errorf("extractFlags name = %q, want suffix %q", name, "model1")
	}
	if strings.TrimSpace(flags) != "-foo bar -baz qux" {
		t.Errorf("extractFlags flags = %q, want %q (ignoring trailing space)", flags, "-foo bar -baz qux")
	}
	if origin != shPath {
		t.Errorf("extractFlags origin = %q, want %q", origin, shPath)
	}
}

func Test_ExtractFlags_FromFilename(t *testing.T) {
	t.Parallel()
	tmp := t.TempDir()
	// Flags encoded in filename
	modelPath := filepath.Join(tmp, "model2&foo=1&bar=2.gguf")
	createGGUFFile(t, tmp, "model2&foo=1&bar=2.gguf", 2048)
	name, flags, origin := extractFlags(modelPath)
	if name == "" {
		t.Errorf("extractFlags name is empty")
	}
	expected := "-foo 1 -bar 2"
	if strings.TrimSpace(flags) != expected {
		t.Errorf("extractFlags flags = %q, want %q (ignoring trailing space)", flags, expected)
	}
	expected = "GGUF filename"
	if origin != expected {
		t.Errorf("extractFlags origin = %q, want %q", origin, expected)
	}
}

func Test_ExtractFlags(t *testing.T) {
	t.Parallel()
	tmp := t.TempDir()
	// No flags
	modelPath := createGGUFFile(t, tmp, "plain_model.gguf", 2048)
	name, flags, origin := extractFlags(modelPath)
	if !strings.HasSuffix(name, "plain_model") {
		t.Errorf("extractFlags name = %q, want suffix %q", name, "plain_model")
	}
	if flags != "" {
		t.Errorf("extractFlags flags = %q, want empty", flags)
	}
	if origin != "" {
		t.Errorf("extractFlags origin = %q, want empty", origin)
	}
}

func TestGetNameAndFlags(t *testing.T) {
	t.Parallel()
	tmp := t.TempDir()
	modelPath := createGGUFFile(t, tmp, "my_model&opt=val.gguf", 2048)
	name, flags, origin := getNameAndFlags(tmp, modelPath)
	if name == "" {
		t.Errorf("getNameAndFlags name is empty")
	}
	if strings.TrimSpace(flags) != "-opt val" {
		t.Errorf("getNameAndFlags flags = %q, want %q (ignoring trailing space)", flags, "-opt val")
	}
	if origin != "GGUF filename" {
		t.Errorf("getNameAndFlags origin = %q, want %q", flags, "GGUF filename")
	}
}

func TestValidateFile(t *testing.T) {
	t.Parallel()

	root := Root{Path: "/home/me/models", FS: fstest.MapFS{
		"valid.gguf":                &fstest.MapFile{Data: make([]byte, 2048)},
		"small.gguf":                &fstest.MapFile{Data: make([]byte, 64)},
		"model-00001-of-00003.gguf": &fstest.MapFile{Data: make([]byte, 1000)},
		"model-00002-of-00003.gguf": &fstest.MapFile{Data: make([]byte, 1000)},
	}}

	// valid
	size, err := verify(root, "valid.gguf")
	if err != nil {
		t.Errorf("validateFile(valid) error: %v", err)
	}
	if size != 2048 {
		t.Errorf("file size: got %d want 2048", size)
	}

	// too small
	_, err = verify(root, "small.gguf")
	if err == nil {
		t.Errorf("validateFile(small) expected error")
	}

	// series first part
	_, err = verify(root, "model-00001-of-00003.gguf")
	if err != nil {
		t.Errorf("validateFile(firstSeries) error: %v", err)
	}

	// series non-first part
	_, err = verify(root, "model-00002-of-00003.gguf")
	if err == nil {
		t.Errorf("validateFile(secondSeries) expected error")
	}
}

func TestValidateModelFiles_NoSwapModels(t *testing.T) {
	t.Parallel()
	tmp := t.TempDir()
	cfg := &Cfg{
		ModelsDir: tmp,
		Swap:      &config.Config{},
	}
	err := cfg.ValidateSwap()
	if err == nil {
		t.Fatalf("validateModelFiles should error when no models and no swap config")
	}
}

func TestValidateModelFiles_WithSwapModels(t *testing.T) {
	t.Parallel()
	tmp := t.TempDir()
	modelPath := createGGUFFile(t, tmp, "ref.gguf", 2048)

	cfg := &Cfg{
		ModelsDir: tmp,
		Swap: &config.Config{
			Models: map[string]*config.ModelConfig{
				"ref": {Cmd: "--model " + modelPath, Unlisted: false},
			},
		},
	}
	err := cfg.ValidateSwap()
	if err != nil {
		t.Fatalf("validateModelFiles error: %v", err)
	}
}

func Test_nameWithGGUF(t *testing.T) {
	t.Parallel()
	tests := []struct{ in, want string }{
		{"ggml-org_gpt-oss-120b-GGUF_gpt-oss-120b-mxfp4", "ggml-org/gpt-oss-120b"},
		{"unsloth_Devstral-2-123B-Instruct-2512-GGUF_UD-Q4_K_XL_Devstral-2-123B-Instruct-2512-UD-Q4_K_XL", "unsloth/Devstral-2-123B-Instruct-2512:UD-Q4_K_XL"},
	}
	for _, tt := range tests {
		t.Run(tt.in, func(t *testing.T) {
			t.Parallel()
			got := nameWithGGUF(tt.in)
			if got != tt.want {
				t.Errorf("nameWithGGUF(%s) -> %q, want %q", tt.in, got, tt.want)
			}
		})
	}
}

func Test_extractModelNameAndFlags(t *testing.T) {
	t.Parallel()

	const (
		script1 = "/path/to/llama-server --host 0.0.0.0 --port 5800 --no-warmup " +
			"	-m /path/model.gguf " +
			`	--load-mode none --chat-template-kwargs '{"reasoning_effort": "high"}' ` +
			"	--reasoning-format auto -c 10240 " + " #	--no-context-shift"

		script2 = `#!/bin/sh
/path/to/llama-server --host 0.0.0.0 --port 5800 \
	--no-warmup --model /path/model.gguf --load-mode none \
	--chat-template-kwargs '{"reasoning_effort": "high"}' \
	--reasoning-format auto -c 10240 \
#	--no-context-shift
`
		script3 = `#!/path/to/llama-server --host 0.0.0.0 --port 5800 \
	--no-warmup -m /path/model.gguf \
	--load-mode none --chat-template-kwargs '{"reasoning_effort": "high"}' \
	--reasoning-format auto -c 10240 \
#	--no-context-shift
`
	)

	root := Root{Path: "/home/me/models", FS: fstest.MapFS{
		"0.sh": &fstest.MapFile{Data: []byte("")},
		"1.sh": &fstest.MapFile{Data: []byte(script1)},
		"2.sh": &fstest.MapFile{Data: []byte(script2)},
		"3.sh": &fstest.MapFile{Data: []byte(script3)},
		"4.sh": &fstest.MapFile{Data: []byte("/path/to/llama-server --models-preset ~/bin/goinfer/models.ini")},
		"5.sh": &fstest.MapFile{Data: []byte("llama-server --model ~/model.gguf")},
		"6.sh": &fstest.MapFile{Data: []byte("/llama-server --model ~/model.gguf")},
		"7.sh": &fstest.MapFile{Data: []byte("/llama-server\t-m\t~/model.gguf\t-c\t0")},
	}}

	tests := []struct{ path, wantModel, wantFlags string }{
		{"1.sh", "/path/model.gguf", `--load-mode none --chat-template-kwargs '{"reasoning_effort": "high"}' 	--reasoning-format auto -c 10240  #	--no-context-shift`},
		{"2.sh", "/path/model.gguf", `--load-mode none --chat-template-kwargs '{"reasoning_effort": "high"}' --reasoning-format auto -c 10240`},
		{"3.sh", "/path/model.gguf", `--load-mode none --chat-template-kwargs '{"reasoning_effort": "high"}' --reasoning-format auto -c 10240`},
		{"4.sh", "", ""},
		{"5.sh", "", ""},
		{"6.sh", "~/model.gguf", ""},
		{"7.sh", "~/model.gguf", "-c\t0"},
	}
	for _, tt := range tests {
		t.Run(tt.path, func(t *testing.T) {
			t.Parallel()
			gotModel, gotFlags := extractModelNameAndFlags(root, tt.path)
			if string(gotModel) != tt.wantModel {
				t.Errorf("extractModelNameAndFlags(%s) = %s, want %s", tt.path, gotModel, tt.wantModel)
			}
			if string(gotFlags) != tt.wantFlags {
				t.Errorf("extractModelNameAndFlags(%s) = %s, want %s", tt.path, gotFlags, tt.wantFlags)
			}
		})
	}
}
