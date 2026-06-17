package findr

import "core:os"
import "core:testing"

@(test)
test_basic_gitignored :: proc(t: ^testing.T) {
	env := create_test_env()
	defer destroy_test_env(&env)

	create_git_repo(env, "repo")
	create_file(env, "repo/.gitignore", "*.env\n")
	create_file(env, "repo/.env")
	create_file(env, "repo/secrets.env")
	create_file(env, "repo/normal.txt")

	assert_output(t, env, nil, {"repo/.env", "repo/secrets.env"})
}

@(test)
test_non_repo_not_scanned :: proc(t: ^testing.T) {
	env := create_test_env()
	defer destroy_test_env(&env)

	create_dir(env, "norepo")
	create_file(env, "norepo/.gitignore", "*.env\n")
	create_file(env, "norepo/.env")

	assert_output_empty(t, env, nil)
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

	assert_output(t, env, nil, {"repo/.env", "repo/secrets.env"})
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

	// dir-only patterns don't produce file results
	assert_output(t, env, nil, {})
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

	assert_output(t, env, nil, {"repo1/a.env", "repo2/secret.key"})
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

	assert_output(t, env, nil, {"parent/top.env", "parent/child/api.key"})
}

@(test)
test_gitignore_in_subdir_ignored :: proc(t: ^testing.T) {
	env := create_test_env()
	defer destroy_test_env(&env)

	create_git_repo(env, "repo")
	create_file(env, "repo/.gitignore", "*.env\n")
	create_dir(env, "repo/sub")
	create_file(env, "repo/sub/.gitignore", "*.txt\n")
	create_file(env, "repo/sub/secret.txt")
	create_file(env, "repo/sub/.env")

	// .gitignore in subdir is not read (flat model).
	// secret.txt should NOT appear (subdir .gitignore ignored).
	// .env should NOT appear (it's nested, not top-level of repo).
	assert_output(t, env, nil, {})
}

@(test)
test_no_gitignore_file :: proc(t: ^testing.T) {
	env := create_test_env()
	defer destroy_test_env(&env)

	create_git_repo(env, "repo")
	create_file(env, "repo/.env")

	assert_output_empty(t, env, nil)
}

@(test)
test_empty_gitignore :: proc(t: ^testing.T) {
	env := create_test_env()
	defer destroy_test_env(&env)

	create_git_repo(env, "repo")
	create_file(env, "repo/.gitignore", "\n\n# comment\n\n")
	create_file(env, "repo/.env")

	assert_output_empty(t, env, nil)
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

	thread_count := os.get_processor_core_count()
	walk(dir1, &results, thread_count)
	walk(dir2, &results, thread_count)
	testing.expect_value(t, len(results), 2)
}

