# Use the official OSRM image as the base
FROM ghcr.io/project-osrm/osrm-backend:v6.0.0

# Copy your processed map data from the repo into the Docker image
# This assumes your data is in a folder named 'osrm-data'
# If your folder is named 'assets', change the line below to: COPY ./assets /data
COPY ./assets /data

# Expose the default OSRM port
EXPOSE 5000

# The default command. We will override this in the Render dashboard.
CMD ["osrm-routed", "--algorithm", "mld", "/data/draft3.bike.osrm"]