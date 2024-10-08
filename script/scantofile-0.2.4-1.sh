#!/bin/bash
# $1 = scanner device
# $2 = friendly name

{
  #override environment, as brscan is screwing it up:
  export $(grep -v '^#' /opt/brother/scanner/env.txt | xargs)

  resolution="${RESOLUTION:-300}"

  gm_opts=(-page A4+0+0)
  if [ "$USE_JPEG_COMPRESSION" = "true" ]; then
    gm_opts+=(-compress JPEG -quality 80)
  fi

  device="$1"
  date=$(date +%Y-%m-%d-%H-%M-%S)

  mkdir -p "/tmp/$date"
  cd "/tmp/$date" || exit
  filename_base="/tmp/${date}/${date}-front-page"
  output_file="${filename_base}%04d.pnm"
  echo "filename: $output_file"

  if [ "$(which usleep 2>/dev/null)" != '' ]; then
    usleep 100000
  else
    sleep 0.1
  fi
  scanimage ${scan_args[@]} --device-name="$device"
  if [ ! -s "${filename_base}0001.pnm" ]; then
    if [ "$(which usleep 2>/dev/null)" != '' ]; then
      usleep 1000000
    else
      sleep 1
    fi
    scanimage ${scan_args[@]} --device-name="$device"
  fi

  #only convert when no back pages are being scanned:
  (
    if [ "$(which usleep 2>/dev/null)" != '' ]; then
      usleep 120000000
    else
      sleep 120
    fi

    (
      echo "converting to PDF for $date..."
      gm convert ${gm_opts[@]} "$filename_base"*.pnm "/scans/${date}.pdf"
      /opt/brother/scanner/brscan-skey/script/trigger_inotify.sh "${SSH_USER}" "${SSH_PASSWORD}" "${SSH_HOST}" "${SSH_PATH}" "${date}.pdf"

      echo "cleaning up for $date..."
      cd /scans || exit
      rm -rf "$date"

      if [ -z "${OCR_SERVER}" ] || [ -z "${OCR_PORT}" ] || [ -z "${OCR_PATH}" ]; then
        echo "OCR environment variables not set, skipping OCR."
      else
        echo "starting OCR for $date..."
        (
          curl -F "userfile=@/scans/$date.pdf" -H "Expect:" -o /scans/"$date"-ocr.pdf "${OCR_SERVER}":"${OCR_PORT}"/"${OCR_PATH}"
          /opt/brother/scanner/brscan-skey/script/trigger_inotify.sh "${SSH_USER}" "${SSH_PASSWORD}" "${SSH_HOST}" "${SSH_PATH}" "${date}-ocr.pdf"
          /opt/brother/scanner/brscan-skey/script/sendtoftps.sh \
            "${FTP_USER}" \
            "${FTP_PASSWORD}" \
            "${FTP_HOST}" \
            "${FTP_PATH}" \
            "${date}.pdf"
        ) &
      fi
    ) &
  ) &
  echo $! >scan_pid
  echo "conversion process for $date is running in PID: $(cat scan_pid)"

} >>/var/log/scanner.log 2>&1
