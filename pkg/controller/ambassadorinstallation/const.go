package ambassadorinstallation

var (
	// DefRegistry is the default registry
	// note: this value can overwritten from the environment when compiling
	// TODO: we could obtain the value from the image of the operator's Deployment maybe?
	DefRegistry = "docker.io/datawire"
)
