{{ define "members" }}

{{- range .Members }}
{{- if not (hiddenMember .)}}

* `{{ fieldName . }}` - {{ if linkForType .Type }}<a href="{{ linkForType .Type}}">{{ typeDisplayName .Type }}</a>{{ else }}{{ typeDisplayName .Type }}{{ end }}
{{- if fieldEmbedded . -}}
    _(Members of `{{ fieldName . }}` are embedded into this type.)_
{{- end}}
{{- if isOptionalMember . -}} _(Optional)_ {{- end }}
{{- if .CommentLines -}}
   {{- safe (renderComments .CommentLines) | fromHTML | indent 2 | toHTML -}}
{{- else -}}
   _(no description)_
{{- end }}
{{- if and (eq (.Type.Name.Name) "ObjectMeta") }}
   Refer to the Kubernetes API documentation for the fields of the `metadata` field.
{{- end -}}

{{ end }}
{{ end }}

{{ end }}