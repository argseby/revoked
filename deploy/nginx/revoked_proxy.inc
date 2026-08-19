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

# Large enough for a file field, small enough not to be a free upload target.
client_max_body_size 32m;
