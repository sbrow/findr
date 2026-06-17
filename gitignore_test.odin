package findr

import "core:testing"

@(test)
test_glob_simple :: proc(t: ^testing.T) {
	result := glob_to_regex("foo", false)
	defer delete(result)
	testing.expect_value(t, result, "(^|/)foo$")
}

@(test)
test_glob_anchored :: proc(t: ^testing.T) {
	result := glob_to_regex("foo", true)
	defer delete(result)
	testing.expect_value(t, result, "^foo$")
}

@(test)
test_glob_star :: proc(t: ^testing.T) {
	result := glob_to_regex("*.log", false)
	defer delete(result)
	testing.expect_value(t, result, "(^|/)[^/]*\\.log$")
}

@(test)
test_glob_question :: proc(t: ^testing.T) {
	result := glob_to_regex("?.log", false)
	defer delete(result)
	testing.expect_value(t, result, "(^|/)[^/]\\.log$")
}

@(test)
test_glob_char_class :: proc(t: ^testing.T) {
	result := glob_to_regex("[abc].log", false)
	defer delete(result)
	testing.expect_value(t, result, "(^|/)[abc]\\.log$")
}

@(test)
test_glob_negated_class :: proc(t: ^testing.T) {
	result := glob_to_regex("[!abc].log", false)
	defer delete(result)
	testing.expect_value(t, result, "(^|/)[^abc]\\.log$")
}

@(test)
test_glob_dot_escaped :: proc(t: ^testing.T) {
	result := glob_to_regex(".env", false)
	defer delete(result)
	testing.expect_value(t, result, "(^|/)\\.env$")
}

@(test)
test_glob_globstar_prefix :: proc(t: ^testing.T) {
	result := glob_to_regex("**/foo", false)
	defer delete(result)
	testing.expect_value(t, result, "(^|/)(.*/)?foo$")
}

@(test)
test_glob_globstar_suffix :: proc(t: ^testing.T) {
	result := glob_to_regex("abc/**", false)
	defer delete(result)
	testing.expect_value(t, result, "(^|/)abc/.*$")
}

@(test)
test_glob_globstar_middle :: proc(t: ^testing.T) {
	result := glob_to_regex("foo/**/bar", false)
	defer delete(result)
	testing.expect_value(t, result, "(^|/)foo/(.*/)?bar$")
}

@(test)
test_glob_backslash_escape :: proc(t: ^testing.T) {
	result := glob_to_regex("\\!foo", false)
	defer delete(result)
	testing.expect_value(t, result, "(^|/)!foo$")
}

@(test)
test_glob_hash_escaped :: proc(t: ^testing.T) {
	result := glob_to_regex("#foo", false)
	defer delete(result)
	testing.expect_value(t, result, "(^|/)\\#foo$")
}

@(test)
test_glob_hash_in_pattern :: proc(t: ^testing.T) {
	result := glob_to_regex("#*#", false)
	defer delete(result)
	testing.expect_value(t, result, "(^|/)\\#[^/]*\\#$")
}

@(test)
test_glob_empty :: proc(t: ^testing.T) {
	result := glob_to_regex("", false)
	defer delete(result)
	testing.expect_value(t, result, "(^|/)$")
}

@(test)
test_is_ignored_basic :: proc(t: ^testing.T) {
	gi := parse("*.env\n")
	defer destroy(&gi)

	testing.expect_value(t, is_ignored(&gi, ".env", false), true)
	testing.expect_value(t, is_ignored(&gi, "foo.env", false), true)
	testing.expect_value(t, is_ignored(&gi, ".env.local", false), false)
	testing.expect_value(t, is_ignored(&gi, "config.yaml", false), false)
}

@(test)
test_is_ignored_negation :: proc(t: ^testing.T) {
	gi := parse("*.env\n!.env.production\n")
	defer destroy(&gi)

	testing.expect_value(t, is_ignored(&gi, ".env", false), true)
	testing.expect_value(t, is_ignored(&gi, ".env.production", false), false)
}

@(test)
test_is_ignored_dir_only :: proc(t: ^testing.T) {
	gi := parse("node_modules/\n")
	defer destroy(&gi)

	testing.expect_value(t, is_ignored(&gi, "node_modules", true), true)
	testing.expect_value(t, is_ignored(&gi, "node_modules", false), false)
}

@(test)
test_is_ignored_anchored :: proc(t: ^testing.T) {
	gi := parse("/secret.key\n")
	defer destroy(&gi)

	testing.expect_value(t, is_ignored(&gi, "secret.key", false), true)
}

@(test)
test_is_ignored_comments_skipped :: proc(t: ^testing.T) {
	gi := parse("# this is a comment\n#another\n*.tmp\n")
	defer destroy(&gi)

	testing.expect_value(t, len(gi.rules), 1)
	testing.expect_value(t, is_ignored(&gi, "file.tmp", false), true)
}

@(test)
test_is_ignored_blank_lines_skipped :: proc(t: ^testing.T) {
	gi := parse("\n\n  \n*.log\n\n")
	defer destroy(&gi)

	testing.expect_value(t, len(gi.rules), 1)
}

@(test)
test_is_ignored_last_match_wins :: proc(t: ^testing.T) {
	gi := parse("*.env\n!*.env\n")
	defer destroy(&gi)

	testing.expect_value(t, is_ignored(&gi, ".env", false), false)
}

@(test)
test_is_ignored_no_rules :: proc(t: ^testing.T) {
	gi := parse("")
	defer destroy(&gi)

	testing.expect_value(t, is_ignored(&gi, "anything", false), false)
}

@(test)
test_is_ignored_env_pattern :: proc(t: ^testing.T) {
	gi := parse(".env*\n")
	defer destroy(&gi)

	testing.expect_value(t, is_ignored(&gi, ".env", false), true)
	testing.expect_value(t, is_ignored(&gi, ".env.local", false), true)
	testing.expect_value(t, is_ignored(&gi, ".envrc", false), true)
}

@(test)
test_is_ignored_globstar :: proc(t: ^testing.T) {
	gi := parse("**/cache\n")
	defer destroy(&gi)

	testing.expect_value(t, is_ignored(&gi, "cache", false), true)
	testing.expect_value(t, is_ignored(&gi, "foo/cache", false), true)
	testing.expect_value(t, is_ignored(&gi, "foo/bar/cache", false), true)
}

@(test)
test_star_negation_subpath :: proc(t: ^testing.T) {
	gi := parse("*\n!public/\n")
	defer destroy(&gi)

	// public dir itself is un-ignored
	testing.expect_value(t, is_ignored(&gi, "public", true), false)
	// children of public/ should still be ignored by *
	testing.expect_value(t, is_ignored(&gi, "public/uuid-dir", true), true)
	testing.expect_value(t, is_ignored(&gi, "public/uuid-dir/file.txt", false), true)
}

@(test)
test_is_ignored_hash_pattern :: proc(t: ^testing.T) {
	gi := parse("\\#*\\#\n")
	defer destroy(&gi)

	testing.expect_value(t, is_ignored(&gi, "#foo#", false), true)
	testing.expect_value(t, is_ignored(&gi, "#test#", false), true)
	testing.expect_value(t, is_ignored(&gi, "AUTHORS", false), false)
	testing.expect_value(t, is_ignored(&gi, "build.zig", false), false)
	testing.expect_value(t, is_ignored(&gi, "ChangeLog", false), false)
}

