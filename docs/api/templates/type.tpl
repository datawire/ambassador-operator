{{ define "type" }}

## <a name="{{ anchorIDForType . }}">`{{- .Name.Name }}`{{ if eq .Kind "Alias" }}(`{{.Underlying}}` alias){{ end -}}
{{ with (typeReferences .) }}
   _(Appears on:
   {{- $prev := "" -}}
   {{- range . -}}
      {{- if $prev -}}, {{- end -}}
      {{- $prev = . -}}
      <a href="{{ linkForType . }}">{{ typeDisplayName . }}</a>
   {{- end -}}
   )_
{{ end }}

{{ safe (renderComments .CommentLines) }}

{{ if .Members }}

{{- if isExportedType . -}}
* `apiVersion` - _string_
  ` {{apiGroup .}} `

* `kind` - _string_
  `{{.Name.Name}}`
{{- end -}}

{{- template "members" . -}}

{{ end }}
{{ end }}

