sudo /opt/Citrix/VDA/bin/ctxreg set \
  -k "HKLM\Software\Citrix\VirtualDesktopAgent" \
  -v "ListOfDDCs" \
  -d "controllers FQDN"
