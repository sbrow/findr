package findr

import "core:os"
import "core:strings"
import "core:sys/linux"
import "core:testing"

// ============================================================================
// .Ignored mode tests (original findr behavior — emit ONLY gitignored files)
// ============================================================================

@(test)
test_basic_gitignored :: proc(t: ^testing.T) {
	env := create_test_env()
	defer destroy_test_env(&env)

	create_git_repo(env, "repo")
	create_file(env, "repo/.gitignore", "*.env\n")
	create_file(env, "repo/.env")
	create_file(env, "repo/secrets.env")
	create_file(env, "repo/normal.txt")

	assert_output(t, env, nil, {include_hidden = true, ignore_mode = .Ignored}, {
		"repo/.env", "repo/secrets.env",
	})
}

@(test)
test_non_repo_not_scanned :: proc(t: ^testing.T) {
	env := create_test_env()
	defer destroy_test_env(&env)

	create_dir(env, "norepo")
	create_file(env, "norepo/.gitignore", "*.env\n")
	create_file(env, "norepo/.env")

	assert_output_empty(t, env, nil, {include_hidden = true, ignore_mode = .Ignored})
}

@(test)
test_negation_pattern :: proc(t: ^testing.T) {
	env := create_test_env()
	defer destroy_test_env(&env)

	create_git_repo(env, "repo")
	create_file(env, "repo/.gitignore", "*.env\n!prod.env\n")
	create_file(env, "repo/.env")
	create_file(env, "repo/secrets.env")
	create_file(env, "repo/prod.env")

	assert_output(t, env, nil, {include_hidden = true, ignore_mode = .Ignored}, {
		"repo/.env", "repo/secrets.env",
	})
}

@(test)
test_dir_only_pattern :: proc(t: ^testing.T) {
	env := create_test_env()
	defer destroy_test_env(&env)

	create_git_repo(env, "repo")
	create_file(env, "repo/.gitignore", "node_modules/\n")
	create_file(env, "repo/node_modules", "should not match (it's a file)")

	create_dir(env, "repo/ignored_dir")
	create_file(env, "repo/.gitignore", "ignored_dir/\n")

	assert_output(t, env, nil, {include_hidden = true, ignore_mode = .Ignored}, {
		"repo/ignored_dir/",
	})
}

@(test)
test_multiple_repos :: proc(t: ^testing.T) {
	env := create_test_env()
	defer destroy_test_env(&env)

	create_git_repo(env, "repo1")
	create_file(env, "repo1/.gitignore", "*.env\n")
	create_file(env, "repo1/a.env")

	create_git_repo(env, "repo2")
	create_file(env, "repo2/.gitignore", "*.key\n")
	create_file(env, "repo2/secret.key")

	assert_output(t, env, nil, {include_hidden = true, ignore_mode = .Ignored}, {
		"repo1/a.env", "repo2/secret.key",
	})
}

@(test)
test_nested_repos :: proc(t: ^testing.T) {
	env := create_test_env()
	defer destroy_test_env(&env)

	create_git_repo(env, "parent")
	create_file(env, "parent/.gitignore", "*.env\n")
	create_file(env, "parent/top.env")

	create_git_repo(env, "parent/child")
	create_file(env, "parent/child/.gitignore", "*.key\n")
	create_file(env, "parent/child/api.key")

	assert_output(t, env, nil, {include_hidden = true, ignore_mode = .Ignored}, {
		"parent/top.env", "parent/child/api.key",
	})
}

@(test)
test_nested_gitignore_read :: proc(t: ^testing.T) {
	env := create_test_env()
	defer destroy_test_env(&env)

	create_git_repo(env, "repo")
	create_file(env, "repo/.gitignore", "*.env\n")
	create_dir(env, "repo/sub")
	create_file(env, "repo/sub/.gitignore", "*.txt\n")
	create_file(env, "repo/sub/secret.txt")
	create_file(env, "repo/sub/.env")

	// Both root and nested .gitignore are read.
	// secret.txt: ignored by sub/.gitignore (*.txt)
	// .env: ignored by root .gitignore (*.env)
	assert_output(t, env, nil, {include_hidden = true, ignore_mode = .Ignored}, {
		"repo/sub/secret.txt", "repo/sub/.env",
	})
}

@(test)
test_nested_gitignore_negation :: proc(t: ^testing.T) {
	env := create_test_env()
	defer destroy_test_env(&env)

	create_git_repo(env, "repo")
	create_file(env, "repo/.gitignore", "*.log\n")
	create_dir(env, "repo/sub")
	create_file(env, "repo/sub/.gitignore", "!important.log\n")
	create_file(env, "repo/sub/important.log")
	create_file(env, "repo/sub/debug.log")

	// Nested negation overrides root pattern.
	// important.log: un-ignored by sub/.gitignore → NOT emitted in .Ignored mode
	// debug.log: still ignored by root → emitted
	assert_output(t, env, nil, {include_hidden = true, ignore_mode = .Ignored}, {
		"repo/sub/debug.log",
	})
}

@(test)
test_nested_gitignore_respected_mode :: proc(t: ^testing.T) {
	env := create_test_env()
	defer destroy_test_env(&env)

	create_git_repo(env, "repo")
	create_file(env, "repo/.gitignore", "*.log\n")
	create_dir(env, "repo/sub")
	create_file(env, "repo/sub/.gitignore", "!important.log\n")
	create_file(env, "repo/sub/important.log")
	create_file(env, "repo/sub/debug.log")

	// In .Respected mode:
	// important.log: un-ignored by nested negation → emitted
	// debug.log: ignored by root → skipped
	assert_output(t, env, nil, {include_hidden = true, ignore_mode = .Respected}, {
		"repo/", "repo/.gitignore", "repo/sub/", "repo/sub/.gitignore", "repo/sub/important.log",
	})
}

@(test)
test_multisegment_pattern :: proc(t: ^testing.T) {
	env := create_test_env()
	defer destroy_test_env(&env)

	create_git_repo(env, "repo")
	create_file(env, "repo/.gitignore", "build/output.txt\n")
	create_dir(env, "repo/build")
	create_file(env, "repo/build/output.txt")
	create_file(env, "repo/build/other.txt")
	create_file(env, "repo/output.txt")

	// Multi-segment pattern matches relative path, not just basename.
	// build/output.txt: matches → ignored
	// build/other.txt: doesn't match → not ignored
	// output.txt: doesn't match (needs build/ prefix) → not ignored
	assert_output(t, env, nil, {include_hidden = true, ignore_mode = .Ignored}, {
		"repo/build/output.txt",
	})
}

@(test)
test_no_gitignore_file :: proc(t: ^testing.T) {
	env := create_test_env()
	defer destroy_test_env(&env)

	create_git_repo(env, "repo")
	create_file(env, "repo/.env")

	assert_output_empty(t, env, nil, {include_hidden = true, ignore_mode = .Ignored})
}

@(test)
test_empty_gitignore :: proc(t: ^testing.T) {
	env := create_test_env()
	defer destroy_test_env(&env)

	create_git_repo(env, "repo")
	create_file(env, "repo/.gitignore", "\n\n# comment\n\n")
	create_file(env, "repo/.env")

	assert_output_empty(t, env, nil, {include_hidden = true, ignore_mode = .Ignored})
}

@(test)
test_multiple_search_dirs :: proc(t: ^testing.T) {
	env := create_test_env()
	defer destroy_test_env(&env)

	create_git_repo(env, "dir1/repo")
	create_file(env, "dir1/repo/.gitignore", "*.env\n")
	create_file(env, "dir1/repo/a.env")

	create_git_repo(env, "dir2/repo")
	create_file(env, "dir2/repo/.gitignore", "*.env\n")
	create_file(env, "dir2/repo/b.env")

	dir1 := join_path(env.temp_dir, "dir1")
	defer delete(dir1)
	dir2 := join_path(env.temp_dir, "dir2")
	defer delete(dir2)

	results := make([dynamic]string)
	defer {
		for r in results {delete(r)}
		delete(results)
	}

	opts := WalkOptions{include_hidden = true, ignore_mode = .Ignored}
	thread_count := os.get_processor_core_count()
	walk(dir1, &results, opts, thread_count)
	walk(dir2, &results, opts, thread_count)
	testing.expect_value(t, len(results), 2)
}

// ============================================================================
// .All mode tests (fd -HI parity — ignore gitignore entirely)
// ============================================================================

@(test)
test_all_mode_emits_all_files :: proc(t: ^testing.T) {
	env := create_test_env()
	defer destroy_test_env(&env)

	create_git_repo(env, "repo")
	create_file(env, "repo/.gitignore", "*.env\n")
	create_file(env, "repo/.env")
	create_file(env, "repo/secrets.env")
	create_file(env, "repo/normal.txt")

	assert_output(t, env, nil, {include_hidden = true, ignore_mode = .All}, {
		"repo/", "repo/.env", "repo/.gitignore", "repo/secrets.env", "repo/normal.txt",
	})
}

@(test)
test_all_mode_descends_everywhere :: proc(t: ^testing.T) {
	env := create_test_env()
	defer destroy_test_env(&env)

	create_git_repo(env, "repo")
	create_file(env, "repo/.gitignore", "build/\n")
	create_dir(env, "repo/build")
	create_file(env, "repo/build/output.txt")

	assert_output(t, env, nil, {include_hidden = true, ignore_mode = .All}, {
		"repo/", "repo/.gitignore", "repo/build/", "repo/build/output.txt",
	})
}

// ============================================================================
// .Respected mode tests (fd -H parity — skip gitignored, prune ignored dirs)
// ============================================================================

@(test)
test_respected_mode_skips_gitignored :: proc(t: ^testing.T) {
	env := create_test_env()
	defer destroy_test_env(&env)

	create_git_repo(env, "repo")
	create_file(env, "repo/.gitignore", "*.env\n")
	create_file(env, "repo/.env")
	create_file(env, "repo/secrets.env")
	create_file(env, "repo/normal.txt")

	assert_output(t, env, nil, {include_hidden = true, ignore_mode = .Respected}, {
		"repo/", "repo/.gitignore", "repo/normal.txt",
	})
}

@(test)
test_respected_mode_prunes_ignored_dirs :: proc(t: ^testing.T) {
	env := create_test_env()
	defer destroy_test_env(&env)

	create_git_repo(env, "repo")
	create_file(env, "repo/.gitignore", "build/\n")
	create_dir(env, "repo/build")
	create_file(env, "repo/build/output.txt")
	create_file(env, "repo/main.txt")

	assert_output(t, env, nil, {include_hidden = true, ignore_mode = .Respected}, {
		"repo/", "repo/.gitignore", "repo/main.txt",
	})
}

// ============================================================================
// Filter tests (excludes, pattern, hidden)
// ============================================================================

@(test)
test_excludes_prune_dirs :: proc(t: ^testing.T) {
	env := create_test_env()
	defer destroy_test_env(&env)

	create_git_repo(env, "repo")
	create_file(env, "repo/.gitignore", "*.env\n")
	create_file(env, "repo/.env")
	create_dir(env, "repo/vendor")
	create_file(env, "repo/vendor/lib.env")

	assert_output(t, env, nil,
		{include_hidden = true, ignore_mode = .Ignored, excludes = {"vendor"}},
		{"repo/.env"},
	)
}

@(test)
test_pattern_filters_results :: proc(t: ^testing.T) {
	env := create_test_env()
	defer destroy_test_env(&env)

	create_git_repo(env, "repo")
	create_file(env, "repo/.gitignore", "*.env\n*.key\n")
	create_file(env, "repo/.env")
	create_file(env, "repo/secrets.env")
	create_file(env, "repo/master.key")

	assert_output(t, env, nil,
		{pattern = "\\.env$", include_hidden = true, ignore_mode = .Ignored},
		{"repo/.env", "repo/secrets.env"},
	)
}

@(test)
test_no_hidden_skips_dotfiles :: proc(t: ^testing.T) {
	env := create_test_env()
	defer destroy_test_env(&env)

	create_git_repo(env, "repo")
	create_file(env, "repo/.gitignore", "*.env\n")
	create_file(env, "repo/.env")
	create_file(env, "repo/secrets.env")
	create_file(env, "repo/.hidden.env")

	assert_output(t, env, nil,
		{include_hidden = false, ignore_mode = .Ignored},
		{"repo/secrets.env"},
	)
}

// ============================================================================
// Special file type tests (SOCK, FIFO, CHR, BLK parity with fd)
// ============================================================================

@(test)
test_fifo_emitted :: proc(t: ^testing.T) {
	env := create_test_env()
	defer destroy_test_env(&env)

	create_git_repo(env, "repo")
	create_file(env, "repo/.gitignore", "*.env\n")

	fifo_path := join_path(env.temp_dir, "repo/test.fifo")
	defer delete(fifo_path)
	cpath := strings.clone_to_cstring(fifo_path)
	defer delete(cpath)
	linux.mknod(cpath, linux.S_IFIFO | linux.Mode{.IRUSR, .IWUSR}, 0)

	assert_output(t, env, nil,
		{include_hidden = true, ignore_mode = .All},
		{"repo/", "repo/.gitignore", "repo/test.fifo"},
	)
}

// ============================================================================
// .ignore file support tests (fd respects .ignore in addition to .gitignore)
// ============================================================================

@(test)
test_ignore_file_respected :: proc(t: ^testing.T) {
	env := create_test_env()
	defer destroy_test_env(&env)

	create_git_repo(env, "repo")
	create_file(env, "repo/.ignore", "*.tmp\n")
	create_file(env, "repo/file.tmp")
	create_file(env, "repo/file.txt")

	assert_output(t, env, nil,
		{include_hidden = true, ignore_mode = .Respected},
		{"repo/", "repo/.ignore", "repo/file.txt"},
	)
}

@(test)
test_ignore_overrides_gitignore :: proc(t: ^testing.T) {
	env := create_test_env()
	defer destroy_test_env(&env)

	create_git_repo(env, "repo")
	create_file(env, "repo/.gitignore", "*.log\n")
	create_file(env, "repo/.ignore", "important.log\n")
	create_file(env, "repo/debug.log")
	create_file(env, "repo/important.log")

	assert_output(t, env, nil,
		{include_hidden = true, ignore_mode = .Respected},
		{"repo/", "repo/.gitignore", "repo/.ignore"},
	)
}
