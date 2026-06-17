package findr

import "core:testing"

@(test)
test_glob_simple :: proc(t: ^testing.T) {
	testing.expect(t, glob_match("foo", "foo", false))
	testing.expect(t, glob_match("foo", "bar/foo", false))
	testing.expect(t, !glob_match("foo", "foobar", false))
	testing.expect(t, !glob_match("foo", "foo/bar", false))
}

@(test)
test_glob_anchored :: proc(t: ^testing.T) {
	testing.expect(t, glob_match("foo", "foo", true))
	testing.expect(t, !glob_match("foo", "bar/foo", true))
	testing.expect(t, !glob_match("foo", "foobar", true))
}

@(test)
test_glob_star :: proc(t: ^testing.T) {
	testing.expect(t, glob_match("*.log", "test.log", false))
	testing.expect(t, glob_match("*.log", ".log", false))
	testing.expect(t, !glob_match("*.log", "test.txt", false))
	testing.expect(t, !glob_match("*.log", "dir/test", false))
}

@(test)
test_glob_question :: proc(t: ^testing.T) {
	testing.expect(t, glob_match("?.log", "a.log", false))
	testing.expect(t, !glob_match("?.log", "ab.log", false))
	testing.expect(t, !glob_match("?.log", ".log", false))
}

@(test)
test_glob_char_class :: proc(t: ^testing.T) {
	testing.expect(t, glob_match("[abc].log", "a.log", false))
	testing.expect(t, glob_match("[abc].log", "b.log", false))
	testing.expect(t, !glob_match("[abc].log", "d.log", false))
}

@(test)
test_glob_negated_class :: proc(t: ^testing.T) {
	testing.expect(t, glob_match("[!abc].log", "d.log", false))
	testing.expect(t, !glob_match("[!abc].log", "a.log", false))
}

@(test)
test_glob_dot_literal :: proc(t: ^testing.T) {
	testing.expect(t, glob_match(".env", ".env", false))
	testing.expect(t, glob_match(".env", "dir/.env", false))
	testing.expect(t, !glob_match(".env", "env", false))
	testing.expect(t, !glob_match(".env", "x.env", false))
}

@(test)
test_glob_globstar_prefix :: proc(t: ^testing.T) {
	testing.expect(t, glob_match("**/foo", "foo", false))
	testing.expect(t, glob_match("**/foo", "a/b/foo", false))
	testing.expect(t, !glob_match("**/foo", "foobar", false))
	testing.expect(t, !glob_match("**/foo", "a/foobar", false))
}

@(test)
test_glob_globstar_suffix :: proc(t: ^testing.T) {
	testing.expect(t, glob_match("abc/**", "abc/x", false))
	testing.expect(t, glob_match("abc/**", "abc/x/y", false))
	testing.expect(t, !glob_match("abc/**", "abc", false))
	testing.expect(t, !glob_match("abc/**", "abcd/x", false))
}

@(test)
test_glob_globstar_middle :: proc(t: ^testing.T) {
	testing.expect(t, glob_match("foo/**/bar", "foo/bar", false))
	testing.expect(t, glob_match("foo/**/bar", "foo/x/bar", false))
	testing.expect(t, !glob_match("foo/**/bar", "foo/barx", false))
	testing.expect(t, !glob_match("foo/**/bar", "foo/x/y/baz", false))
}

@(test)
test_glob_backslash_escape :: proc(t: ^testing.T) {
	testing.expect(t, glob_match("\\!foo", "!foo", false))
	testing.expect(t, !glob_match("\\!foo", "foo", false))
}

@(test)
test_glob_hash_literal :: proc(t: ^testing.T) {
	testing.expect(t, glob_match("#foo", "#foo", false))
	testing.expect(t, !glob_match("#foo", "foo", false))
}

@(test)
test_glob_hash_pattern :: proc(t: ^testing.T) {
	testing.expect(t, glob_match("#*#", "#test#", false))
	testing.expect(t, glob_match("#*#", "##", false))
	testing.expect(t, !glob_match("#*#", "test", false))
	testing.expect(t, !glob_match("#*#", "#test", false))
}

@(test)
test_glob_empty :: proc(t: ^testing.T) {
	testing.expect(t, glob_match("", "", false))
	testing.expect(t, !glob_match("", "foo", false))
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

