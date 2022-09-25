Set-Location ./DTAZUREEXECUTION/JMeter_Base_Image
# Get-ChildItem
docker login -u satheeshpandianj -p Adhira_2312
docker build -t satheeshpandianj/jmeterbase:latest .
docker push satheeshpandianj/jmeterbase:latest

Set-Location ../JMeter_Master_Image
# Get-ChildItem
docker build -t satheeshpandianj/jmetermaster:latest .
docker push satheeshpandianj/jmetermaster:latest

Set-Location ../JMeter_Slave_Image
# Get-ChildItem
docker build -t satheeshpandianj/jmeterslave:latest .
docker push satheeshpandianj/jmeterslave:latest

Clear-Host
docker images
