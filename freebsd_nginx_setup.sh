# install dependencies
pkg install git-lite pcre py36-brotli

# Download Google's Nginx brotli module for (.br) file support
cd /tmp && git clone https://github.com/google/ngx_brotli.git && cd /tmp/ngx_brotli && git submodule update --init

# Download OpenSSL v1.1.1-DEV with TLS v1.3 support
cd /tmp && git clone https://github.com/openssl/openssl.git openssl

# Download the latest Nginx 
export VER=1.15.0; cd /tmp && curl -O https://nginx.org/download/nginx-$VER.tar.gz && tar zxvf nginx-*; cd nginx-$VER

# Build Nginx against Openssl and minimal module support

./configure --with-openssl=/tmp/openssl --with-openssl-opt=enable-tls1_3 --prefix=/usr/local/etc/nginx --with-cc-opt='-g -O2 -fPIE -fstack-protector-all --param=ssp-buffer-size=4 -Wformat -Werror=format-security -fPIC -D_FORTIFY_SOURCE=2 -I /usr/local/include' --with-ld-opt='-Wl,-Bsymbolic-functions -fPIE -pie -Wl,-z,relro -Wl,-z,now -fPIC -L /usr/local/lib' --conf-path=/usr/local/etc/nginx/nginx.conf --sbin-path=/usr/local/sbin/nginx --pid-path=/var/run/nginx.pid --error-log-path=/var/log/nginx/error.log --user=www --group=www --modules-path=/usr/local/libexec/nginx --http-log-path=/var/log/nginx/access.log --with-http_ssl_module --with-file-aio --with-http_gzip_static_module --with-pcre --with-http_v2_module --with-threads --without-http-cache --without-http_autoindex_module --without-http_browser_module --without-http_fastcgi_module --without-http_geo_module --without-http_gzip_module --without-http_limit_conn_module --without-http_map_module --without-http_memcached_module --without-poll_module --without-http_proxy_module --without-http_referer_module --without-http_scgi_module --without-select_module --without-http_split_clients_module --without-http_ssi_module --without-http_upstream_ip_hash_module --without-http_upstream_least_conn_module --without-http_upstream_keepalive_module --without-http_userid_module --without-http_uwsgi_module --without-mail_imap_module --without-mail_pop3_module --without-mail_smtp_module --add-module=/tmp/ngx_brotli/  && make && make install && echo SUCCESS
