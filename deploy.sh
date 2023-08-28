#!/bin/bash

echo 'Building and deploying the latest Docker image'

project=$(grep -o '\"project_id\": \"[^\"]*' terraform.tfvars.json | grep -o '[^\"]*$')
region=$(grep -o '\"project_default_region\": \"[^\"]*' terraform.tfvars.json | grep -o '[^\"]*$')

gcloud builds submit --config=cloudbuild.yaml --project=$project --substitutions=_REGION=$region
gcloud run deploy runservice1 --image $region-docker.pkg.dev/$project/run-image/custom-flask:latest --project=$project --region=$region
gcloud run deploy runservice2 --image $region-docker.pkg.dev/$project/run-image/custom-nodejs:latest --project=$project --region=$region
gcloud run deploy frontend --image $region-docker.pkg.dev/$project/run-image/flask-frontend:latest --project=$project --region=$region
