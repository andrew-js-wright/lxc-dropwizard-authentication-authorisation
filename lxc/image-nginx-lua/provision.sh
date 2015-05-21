if ! sudo lxc-ls | grep web-base > /dev/null
then
# Create base web container
sudo lxc-create -t ubuntu -n web-base
sudo lxc-start -n web-base
sleep 5s

sudo lxc-attach -n web-base -- << SCRIPT 
    sudo apt-get update
    sudo ping -c 1 archive.ubuntu.com && apt-get -y --fix-missing install libreadline-dev libncurses5-dev libpcre3-dev libssl-dev perl build-essential curl
    curl -0 http://openresty.org/download/ngx_openresty-1.7.10.1.tar.gz -o ngx_openresty-1.7.10.1.tar.gz
    tar xzvf ngx_openresty-1.7.10.1.tar.gz
    cd ngx_openresty-1.7.10.1
    ./configure --with-luajit --with-http_gzip_static_module --with-http_ssl_module --with-pcre-jit
    make
    make install 
    rm -rf /ngx_openresty-1.7.10.1*
    mkdir /var/log/nginx && touch /var/log/nginx/access.log && touch /var/log/nginx/error.log
    ln -sf /dev/stdout /var/log/nginx/access.log
    ln -sf /dev/stderr /var/log/nginx/error.log
SCRIPT
fi

sudo lxc-stop -n web-base
sudo lxc-destroy -fn web
sudo lxc-clone -o web-base -n web
sudo cp /host/upstart/web.conf /var/lib/lxc/web/rootfs/etc/init/
sudo mkdir -p /var/lib/lxc/web/rootfs/opt/nginx/conf/
sudo cp -R /host/volume-nginx-conf.d/* /var/lib/lxc/web/rootfs/opt/nginx/conf

sudo lxc-start -n web
