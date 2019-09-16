# jsonnet --tla-str org='clo]udfoundry',name='node-engine-cnb' query.jsonnet | http POST https://api.github.com/graphql "Authorization: bearer 81815d627782ed761c486795ebda7bd53bd145fa"
# http https://api.github.com/repos/cloudfoundry/node-engine-cnb/tags | jq -r '.[] | select(.name == "v0.0.51") | .commit.sha'

