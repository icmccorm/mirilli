docker build -t ffickle .
docker volume create results
docker run -d -v results:/results ffickle ./verify $1 /results
mkdir ./export
docker run --rm -v results:/results -v `pwd`/export:/export busybox sh -c 'cp -r /volume /backup'