#!/bin/bash
set -e

echo "Creating deployment package..."

# Create deployment package
cd ~/lambda-shutdown-demo
zip -r lambda-shutdown-demo.zip lambda_function.py extensions/

echo "Package created: lambda-shutdown-demo.zip"
ls -lh lambda-shutdown-demo.zip
