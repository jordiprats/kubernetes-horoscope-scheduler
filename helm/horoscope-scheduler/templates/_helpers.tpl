{{/* vim: set linebreak */ -}}
{{/*
Expand the name of the chart.
*/ -}}
{{- define "horoscope-scheduler.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
*/ -}}
{{- define "horoscope-scheduler.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Create the name of the service account to use
*/ -}}
{{- define "horoscope-scheduler.serviceAccountName" -}}
{{- default (include "horoscope-scheduler.fullname" .) .Values.serviceAccount.name -}}
{{- end -}}
