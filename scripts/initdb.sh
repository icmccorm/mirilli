# This script is meant to be run from the root directory as the user 'postgres' building the Docker image
service postgresql start
sudo -u postgres createuser --superuser root 
# We only attempt to populate the database if it has already been downloaded.
if [ -d "dataset" ]; then
  cd crates-db
  createdb crates
  psql crates < schema.sql
  psql crates < import.sql
  psql -d crates -f ../scripts/population.sql
fi
