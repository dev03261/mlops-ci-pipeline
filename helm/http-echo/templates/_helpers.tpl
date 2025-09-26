{{/* Generate basic labels */}}
{{- define "http-echo.labels" -}}
app: {{ .Values.app.name }}
component: {{ .Values.labels.component }}
{{- end -}}

{{/* Generate selector labels */}}
{{- define "http-echo.selectorLabels" -}}
app: {{ .Values.app.name }}
{{- end -}}