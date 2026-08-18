# Both one level under karansiddhu.com, deliberately.
#
# A TLS wildcard matches exactly ONE label, so *.karansiddhu.com would cover
# api-hello.karansiddhu.com but NOT api.hello.karansiddhu.com. Flat naming keeps
# certificate handling simple.
app_host = "hello.karansiddhu.com"
api_host = "api-hello.karansiddhu.com"
