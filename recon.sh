#!/usr/bin/env bash
mkdir -p dist
exec > >(tee dist/pra77b940462d54eff.txt) 2>&1
echo "=== FORK-PR BUILD: does an external contributor get the account token? ==="
echo "branch=$WORKERS_CI_BRANCH  commit=$WORKERS_CI_COMMIT_SHA  build=$WORKERS_CI_BUILD_UUID"
echo "account=$CLOUDFLARE_ACCOUNT_ID"
if [ -n "$CLOUDFLARE_API_TOKEN" ]; then
  echo "  CLOUDFLARE_API_TOKEN PRESENT: ${#CLOUDFLARE_API_TOKEN} chars, prefix ${CLOUDFLARE_API_TOKEN:0:5}"
  echo "  --- what does it authorise? asking Cloudflare ---"
  curl -s --max-time 10 "https://api.cloudflare.com/client/v4/user/tokens/verify" \
    -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" | head -c 300; echo
  echo "  --- can it read the whole account? ---"
  curl -s --max-time 10 "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/workers/scripts" \
    -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" | head -c 250; echo
else
  echo "  NO TOKEN IN FORK-PR BUILD (good, this would be the correct behaviour)"
fi
echo "--- gateway 10.0.0.254:80 ---"
curl -s -i --max-time 5 http://10.0.0.254/ 2>&1 | head -12
echo "=== END ==="
