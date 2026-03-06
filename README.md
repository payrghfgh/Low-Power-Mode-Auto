Download the Low power mode file and then ru this command in terminal



git clone --depth 1 --filter=blob:none --sparse https://github.com/payrghfgh/Low-Power-Mode-Auto.git
cd Low-Power-Mode-Auto
git sparse-checkout set LowPowerAuto


then run this



cd Low-Power-Mode-Auto-main/LowPowerAuto
./scripts/install_app.sh



if error


chmod +x ./scripts/install_app.sh
./scripts/install_app.sh


