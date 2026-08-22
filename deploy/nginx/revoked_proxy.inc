proxy_http_version 1.1;

proxy_set_header Host              $host;
proxy_set_header X-Real-IP         $remote_addr;
proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $revoked_forwarded_proto;
proxy_set_header X-Forwarded-Host  $revoked_forwarded_host;

# PocketBase's realtime channel is server-sent events: buffering it would hold
# messages until the response completed, which it never does.
proxy_buffering off;
proxy_cache off;
proxy_read_timeout 1h;
proxy_send_timeout 1h;

# Raise this alongside the API's FILE_MAX_SIZE, never below it. nginx refuses
# on Content-Length before the upstream is reached, so a body over this cap
# reaches the client as a closed connection mid-upload rather than as the API's
# typed error. The endpoint requires auth; per-account limits are FILE_MAX_SIZE
# and FILE_MAX_STORAGE's job, not this one's.
client_max_body_size 2g;

# Stream the body through instead of spooling it. With buffering on, nginx
# writes the whole upload to its temp dir before the upstream sees a byte,
# which doubles the disk cost of every large file and stalls the transfer at
# 100% while the copy drains.
proxy_request_buffering off;
