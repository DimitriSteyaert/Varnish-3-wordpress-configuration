# Define backend
backend default {
    .host = "127.0.0.1";
    .port = "8080";
}

# Who is allowed to purge?
acl purgers {
    "localhost";
    "127.0.0.1";
}

sub vcl_recv {

    if (req.request == "PURGE") {
        if (!client.ip ~ purgers) {
            error 405 "You are not allowed to purge";
        }
            return(lookup);
    }

    # Set proxied ip header to original remote address
        set req.http.X-Forwarded-For = client.ip;

    # If the backend fails, keep serving out of the cache for 30m
        set req.grace = 30m;

    # Remove has_js and Google Analytics cookies
        set req.http.Cookie = regsuball(req.http.Cookie, "(^|;\s*)(__[a-z]+|__utm*|has_js)=[^;]*", "");

    # Remove a ";" prefix, if present.
    set req.http.Cookie = regsub(req.http.Cookie, "^;\s*", "");

    # Remove empty cookies.
    if (req.http.Cookie ~ "^\s*$") {
            unset req.http.Cookie;
    }

    # remove double // in urls,
        set req.url = regsuball( req.url, "//", "/"      );

    # Normalize Accept-Encoding
    if (req.http.Accept-Encoding) {
        if (req.url ~ "\.(jpg|png|gif|gz|tgz|bz2|tbz|mp3|ogg)$") {
            # No point in compressing these
            remove req.http.Accept-Encoding;
        } elsif (req.http.Accept-Encoding ~ "gzip") {
            set req.http.Accept-Encoding = "gzip";
        } elsif (req.http.Accept-Encoding ~ "deflate") {
            set req.http.Accept-Encoding = "deflate";
        } else {
            # unknown algorithm
            remove req.http.Accept-Encoding;
        }
    }

    # Remove cookies for static files
    if (req.url ~ "\.(gif|jpg|jpeg|swf|css|js|flv|mp3|mp4|pdf|ico|png|tif|tiff|mp3|htm|html)(\?.*|)$") {
        unset req.http.cookie;
        return(lookup);
    }

    # Disable caching for backend parts
    if ( req.url ~ "^/[^?]+/wp-(login|admin)" || req.url ~ "^/wp-(login|admin)" || req.url ~ "preview=true" ) {
        return(pass);
    }

    # always pass through posted requests and those with basic auth
    if ( req.request == "POST" || req.http.Authorization ) {
        return (pass);
    }

    # Strip cookies for cached content
    unset req.http.Cookie;
    return(lookup);

}

sub vcl_fetch {

    # If the backend fails, keep serving out of the cache for 30m
    set beresp.grace = 30m;
    set beresp.ttl = 48h;

    # Remove some unwanted headers
    unset beresp.http.Server;
    unset beresp.http.X-Powered-By;

    # Respect the Cache-Control=private header from the backend
    if (beresp.http.Cache-Control ~ "private") {
        set beresp.http.X-Cacheable = "NO:Cache-Control=private";
    } elsif (beresp.ttl < 1s) {
        set beresp.ttl   = 5s;
        set beresp.grace = 5s;
        set beresp.http.X-Cacheable = "YES:FORCED";
    } else {
        set beresp.http.X-Cacheable = "YES";
    }

    # Don't cache responses to posted requests or requests with basic auth
    if ( req.request == "POST" || req.http.Authorization ) {
        return (hit_for_pass);
    }

    # Cache error pages for a short while
    if( beresp.status == 404 || beresp.status == 500 || beresp.status == 301 || beresp.status == 302 ){
        set beresp.ttl = 1m;
        return(deliver);
    }

    # Do not cache non-success response
    if( beresp.status != 200 ){
    return(hit_for_pass);
    }

    # Strip cookies before these filetypes are inserted into the cache
    if (req.url ~ "\.(png|gif|jpg|swf|css|js)$") {
        unset beresp.http.set-cookie;
    }

    return(deliver);

}

sub vcl_deliver {

    # Add debugging headers to cache requests
    if (obj.hits > 0) {
        set resp.http.X-Cache = "HIT";
    }
    else {
        set resp.http.X-Cache = "MISS";
    }

}

sub vcl_error {

    # Try connecting to apache 3 times before giving up
    if (obj.status == 503 && req.restarts < 2) {
        set obj.http.X-Restarts = req.restarts;
        return(restart);
    }
    if (obj.status == 301) {
        set obj.http.Location = req.url;
        set obj.status = 301;
        return(deliver);
    }

}

sub vcl_hit {

    if (req.request == "PURGE"){
        set obj.ttl = 0s;
        error 200 "Varnish cache has been purged for this object.";
    }

}

sub vcl_miss {

    if (req.request == "PURGE") {
        error 404 "Object not in cache.";
    }

}
