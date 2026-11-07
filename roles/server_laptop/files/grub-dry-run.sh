# Dry run of the GRUB change for tasks/preflight.yml. Passed on stdin of
#   unshare -m --propagation private sh -s
# (stdin, not an argument: the command module runs expandvars over its arguments
# and would rewrite every $VAR in this text). The body is a function run with
# stdin closed, so nothing it starts can swallow the rest of the script.
#
# In its own mount namespace /etc/default/grub.d is replaced by a temporary copy
# plus the rendered drop-in, and grub-mkconfig prints to stdout. /boot and the
# real /etc are never written.
#
# In:  PREFLIGHT_DROPIN (the rendered drop-in), PREFLIGHT_N (consoleblank seconds)
# Out: "RESULT key=value" lines, then the diffs.
main() {
result() { printf 'RESULT %s=%s\n' "$1" "$2"; }
work=$(mktemp -d) || exit 1
trap 'rm -rf "$work"' EXIT
mkdir "$work/grub.d"
cp -a /etc/default/grub.d/. "$work/grub.d/"
# os-prober would probe other disks; keep it off in both runs.
printf 'GRUB_DISABLE_OS_PROBER=true\n' > "$work/grub.d/zz-preflight-no-os-prober.cfg"
mount --bind "$work/grub.d" /etc/default/grub.d || { result bind_failed 1; exit 0; }

grub-mkconfig > "$work/before" 2> "$work/before.err" < /dev/null
result before_rc $?
printf '%s\n' "$PREFLIGHT_DROPIN" > "$work/grub.d/90-server-laptop.cfg"
grub-mkconfig > "$work/after" 2> "$work/after.err" < /dev/null
result after_rc $?
grub-script-check "$work/after" > "$work/check.err" 2>&1
result check_rc $?
result linux_lines "$(grep -cE '^[[:space:]]*linux(efi)?[[:space:]]' "$work/after")"

# Every difference must be one "linux" line gaining one " consoleblank=N".
awk -v n="$PREFLIGHT_N" '
  FNR == NR { b[FNR] = $0; nb = FNR; next }
  {
    na = FNR
    if ($0 == b[FNR]) next
    tok = " consoleblank=" n
    p = index($0, tok)
    if (p && $0 ~ /^[ \t]*linux(efi)?[ \t]/ &&
        substr($0, 1, p - 1) substr($0, p + length(tok)) == b[FNR]) { changed++; next }
    bad++
  }
  END {
    if (na != nb) bad++
    print "RESULT changed_lines=" changed + 0
    print "RESULT unexpected_lines=" bad + 0
  }' "$work/before" "$work/after"

# What update-grub would change besides our line (a hand edit, a new kernel).
diff /boot/grub/grub.cfg "$work/before" > "$work/drift" 2>&1
result drift_lines "$(wc -l < "$work/drift")"

printf '===DRIFT===\n'; cat "$work/drift"
printf '===CHANGE===\n'; diff "$work/before" "$work/after"
printf '===ERRORS===\n'; tail -n 20 "$work/before.err" "$work/after.err" "$work/check.err"
}
main < /dev/null
