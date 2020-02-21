{{ define "packages" }}

# Packages

{{ range .packages }}
* <a id="{{- packageAnchorID . -}}"> {{- packageDisplayName . -}} </a>
  {{ with (index .GoPackages 0 )}}
    {{- with .DocComments }}
        {{- safe (renderComments .) }}
    {{- end }}
  {{- end }}

# Resource Types

{{ range (visibleTypes (sortedTypes .Types))}}
  {{- template "type" .  }}
{{ end }}

{{ end }}
{{ end }}
