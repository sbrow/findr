package findr

import "core:fmt"
import "core:strings"
import "core:text/regex"

// FIXME: Use a const bit_set[0..<128; u128] here when we start doing optimizations
is_regex_meta :: proc(c: u8) -> bool {
	switch c {
	case '.', '+', '(', ')', '{', '}', '^', '$', '|', '#':
		return true
	}
	return false
}

glob_to_regex :: proc(pattern: string, anchored: bool) -> string {
	// TODO: Attempt to pre-allocate the string builder when we start doing optimizations
	sb: strings.Builder
	strings.builder_init(&sb)
	defer strings.builder_destroy(&sb)

	if anchored {
		fmt.sbprintf(&sb, "^")
	} else {
		fmt.sbprintf(&sb, "(^|/)")
	}

	i := 0
	for i < len(pattern) {
		c := pattern[i]

		if c == '*' {
			if i + 1 < len(pattern) && pattern[i + 1] == '*' {
				prev_slash := i == 0 || pattern[i - 1] == '/'
				at_end := i + 2 >= len(pattern)
				next_slash := !at_end && pattern[i + 2] == '/'

				if prev_slash && (next_slash || at_end) {
					if next_slash {
						i += 3
						fmt.sbprintf(&sb, "(.*/)?")
					} else {
						i += 2
						fmt.sbprintf(&sb, ".*")
					}
				} else {
					fmt.sbprintf(&sb, "[^/]*")
					i += 2
				}
			} else {
				fmt.sbprintf(&sb, "[^/]*")
				i += 1
			}
		} else if c == '?' {
			fmt.sbprintf(&sb, "[^/]")
			i += 1
		} else if c == '[' {
			append(&sb.buf, '[')
			i += 1
			if i < len(pattern) && pattern[i] == '!' {
				append(&sb.buf, '^')
				i += 1
			}
			if i < len(pattern) && pattern[i] == ']' {
				append(&sb.buf, ']')
				i += 1
			}
			for i < len(pattern) && pattern[i] != ']' {
				append(&sb.buf, pattern[i])
				i += 1
			}
			if i < len(pattern) {
				append(&sb.buf, ']')
				i += 1
			}
		} else if c == '\\' {
			i += 1
			if i < len(pattern) {
				if is_regex_meta(pattern[i]) {
					append(&sb.buf, '\\')
				}
				append(&sb.buf, pattern[i])
				i += 1
			}
		} else if is_regex_meta(c) {
			append(&sb.buf, '\\')
			append(&sb.buf, c)
			i += 1
		} else {
			append(&sb.buf, c)
			i += 1
		}
	}

	fmt.sbprintf(&sb, "$")

	s := strings.to_string(sb)
	result, _ := strings.clone(s)
	return result
}

Rule :: struct {
	regex:    regex.Regular_Expression,
	negated:  bool,
	dir_only: bool,
}

Gitignore :: struct {
	rules: [dynamic]Rule,
}

parse :: proc(content: string) -> Gitignore {
	gi: Gitignore
	gi.rules = make([dynamic]Rule)

	remaining := content
	for {
		line, ok := strings.split_lines_iterator(&remaining)
		if !ok do break

		s := strings.trim_space(line)
		if len(s) == 0 do continue
		if s[0] == '#' do continue

		negated := false
		if s[0] == '!' {
			negated = true
			s = s[1:]
		}

		if len(s) > 0 && s[0] == '\\' {
			if len(s) > 1 && (s[1] == '#' || s[1] == '!') {
				s = s[1:]
			}
		}

		dir_only := false
		if len(s) > 0 && s[len(s) - 1] == '/' {
			dir_only = true
			s = s[:len(s) - 1]
		}

		anchored := false
		if len(s) > 0 && s[0] == '/' {
			anchored = true
			s = s[1:]
		}

		if len(s) == 0 do continue

		regex_str := glob_to_regex(s, anchored)
		re, err := regex.create(regex_str, {regex.Flag.No_Capture})
		delete(regex_str)
		if err != nil do continue

		append(&gi.rules, Rule{regex = re, negated = negated, dir_only = dir_only})
	}

	return gi
}

Match :: enum {
	None,
	Ignored,
	Unignored,
}

check_match :: proc(gi: ^Gitignore, path: string, is_dir: bool) -> Match {
	result := Match.None
	for rule in gi.rules {
		if rule.dir_only && !is_dir do continue
		cap, ok := regex.match(rule.regex, path)
		regex.destroy(cap)
		if ok {
			result = rule.negated ? .Unignored : .Ignored
		}
	}
	return result
}

is_ignored :: proc(gi: ^Gitignore, path: string, is_dir: bool) -> bool {
	return check_match(gi, path, is_dir) == .Ignored
}

destroy :: proc(gi: ^Gitignore) {
	for rule in gi.rules {
		regex.destroy(rule.regex)
	}
	delete(gi.rules)
}

