#!/usr/bin/env bash
# Verify every .a in the deps prefix: arm64 only (lipo -archs) and every object has
# platform IOS + minos 18.0 (vtool -show-build on extracted members; vtool cannot read .a directly).
set -uo pipefail
B="$(cd "$(dirname "$0")/.." && pwd)/build"
P="${1:-$B/prefix}/lib"
T="$B/vt"; bad=0
for f in "$P"/*.a; do
  rm -rf "${T:?}"; mkdir -p "$T"
  arch=$(lipo -archs "$f" 2>&1)
  ( cd "$T" && ar x "$f" 2>/dev/null )
  pm=$(find "$T" -name '*.o' -print0 | xargs -0 -n1 -P4 vtool -show-build 2>/dev/null | awk '/platform /{p=$2} /minos /{print p" "$2}' | sort | uniq -c | tr -s ' ' | tr '\n' ';')
  nobj=$(find "$T" -name '*.o' | wc -l | tr -d ' ')
  ok=OK; [ "$pm" = " $nobj IOS 18.0;" ] || ok=CHECK   # every object IOS/18.0
  [ "$arch" = arm64 ] || ok=CHECK
  [ "$ok" = OK ] || bad=1
  echo "$ok $(basename "$f") arch=$arch objs=$nobj $(du -k "$f" | cut -f1)KB [$pm]"
done
rm -rf "${T:?}"
exit $bad
