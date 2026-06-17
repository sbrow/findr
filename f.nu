#!/usr/bin/env nu

def main [] {
  let all = (fd -HI -a .env . ~/ | lines | sort)
  let unignored = (fd -H -a .env ~/ | lines | sort)  

  $all | filter { |it| not ($it in $unignored) } | str join "\n"
  # sorted_list_intersect $all $unignored | str join "\n"
}

def sorted_list_intersect [xs1: list, xs2: list] {
  let len1 = ($xs1 | length)
  let len2 = ($xs2 | length)
  mut i = 0
  mut j = 0
  while ($i < $len1 and $j < $len2) {
    if ($xs1 | get $i) < ($xs2 | get $j) {
      $i = $i + 1
    } else if ($xs2 | get $j) < ($xs1 | get $i) {
      $j = $j + 1
    } else {
      echo ($xs2 | get $j)
      $i = $i + 1
      $j = $j + 1
    }
  }
}
