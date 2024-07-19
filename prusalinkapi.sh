#!/bin/bash
# Version 0.4 beta/test

PRUSA_IP="192.168.1.xx"
PRUSALINK_APIKEY="your.api.key"

PRUSA_POWERON="/home/pi/prusapoweron" # <- Insert your power on console command or script location
PRUSA_POWEROFF="/home/pi/prusapoweroff" # <- Insert your power off console command or script location

###################################

STATUS_API_URL="http://$PRUSA_IP/api/v1/status"
PRINTER_API_URL="http://$PRUSA_IP/api/printer"
JOB_API_URL="http://$PRUSA_IP/api/v1/job"
INFO_API_URL="http://$PRUSA_IP/api/v1/info"

convertir_temps() {
    local secondes="$1"
    local jours=$((secondes / 86400))
    local reste=$((secondes % 86400))
    local heures=$((reste / 3600))
    reste=$((reste % 3600))
    local minutes=$((reste / 60))
    local secondes=$((reste % 60))

	if 	 [ "$jours" -eq 0 ] && [ "$heures" -eq 0 ] && [ "$minutes" -eq 0 ]; then
        echo "$secondes secondes"
	elif [ "$jours" -eq 0 ] && [ "$heures" -eq 0 ]; then
		echo "$minutes minutes, $secondes secondes"
	elif [ "$jours" -eq 0 ]; then
		echo "$heures heures, $minutes minutes, $secondes secondes"
	else
		echo "$jours jours, $heures heures, $minutes minutes, $secondes secondes"
	fi
}

pause_job() {
    local job_id="$1"
    curl -X PUT -H "X-Api-Key: $PRUSALINK_APIKEY" -s "http://$PRUSA_IP/api/v1/job/$job_id/pause"
}

resume_job() {
    local job_id="$1"
    curl -X PUT -H "X-Api-Key: $PRUSALINK_APIKEY" -s "http://$PRUSA_IP/api/v1/job/$job_id/resume"
}

power_off() {
	get_more_info  > /dev/null
	echo " Temp Nozzle (Température de la buse): $status_temp_nozzle °C / $status_target_nozzle °C ($nozzle_percentage%)"
	echo " Temp Bed (Température du plateau):    $status_temp_bed °C / $status_target_bed °C ($bed_percentage%)"
	echo " Fan Hotend (Vitesse du ventilateur de l'extrudeur): $status_fan_hotend tr/min"
	echo " Fan Print (Vitesse du ventilateur l'impression): $status_fan_print tr/min"
	if [ "$nozzle_percentage" == "0" ] && [ "$bed_percentage" == "0" ] && [ "$status_fan_hotend" == "0" ] && [ "$status_fan_print" == "0" ] ; then
		echo "	=> POWER OFF" 
		$PRUSA_POWEROFF
	else
		echo "Nozzle or Bed is Hot, please wait..."
	fi
}
show_help() {
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands for PRUSA:"
    echo "  pause       Pause the current print job."
    echo "  resume      Resume a paused print job."
    echo "  info        Show detailed information about the current print job and printer status."
    echo "  remaining   Wait for the current print job to finish and display a progress bar."
    echo "  on          Power on the printer."
    echo "  off         Power off the printer (if idle and safe to do so)."
	echo "  toggle      Switch power on or power off"
    echo ""
	echo "Commands for ESP32CAM: "
	echo "  capture     Capture a snapshot with the ESP32CAM."
    echo "  send        Capture a snapshot and send to Prusa Connect."
	echo "  send_light  Capture a snapshot with light on and send to Prusa Connect."
    echo "  light_on    Turn on the ESP32CAM light."
    echo "  light_off   Turn off the ESP32CAM light."
    echo "  flash_on    Turn on the ESP32CAM flash."
    echo "  flash_off   Turn off the ESP32CAM flash."
    echo "  reboot      Reboot the ESP32CAM."
    echo "  cam_logs    Get logs from the ESP32CAM."
    echo "  last_photo  Get the last captured photo from the ESP32CAM."
	echo ""
    echo "  help        Show this help message."
}

get_info() {
    # Récupérer les données JSON de l'API de statut avec authentification
	status_response=$(curl -H "X-Api-Key: $PRUSALINK_APIKEY" -s $STATUS_API_URL)
	# Vérifier si la requête de statut a réussi
	if [ $? -ne 0 ]; then
			# echo "Failed to retrieve status data from the API."
			jobstatus=offline
	else #fi

		# Récupérer les données JSON de l'API de job avec authentification
		job_response=$(curl -H "X-Api-Key: $PRUSALINK_APIKEY" -s $JOB_API_URL)
		# Vérifier si la requête de job a réussi
			# if [ $? -ne 0 ]; then
			# echo "Failed to retrieve job data from the API."
				# jobstatus=offline
			# fi

			# Vérifier si la réponse de statut ou job est vide
			# if [ -z "$status_response" ]; then
				# echo "Empty response from the status API."
				# jobstatus=offline
			# elif [ -z "$job_response" ]; then
				# echo "Empty response from the job API."
				# jobstatus=online
			# fi
		status_job_id=$(echo "$status_response" | jq -r '.job.id')
		status_progress=$(echo "$status_response" | jq -r '.job.progress')
		status_printer_state=$(echo "$status_response" | jq -r '.printer.state')
	fi

	# Traduire l'état de l'imprimante en français avec une structure case
	case "$status_printer_state" in
		"PRINTING")	status_printer_state_fr="EN COURS D'IMPRESSION"	;;
		"PAUSED")	status_printer_state_fr="EN PAUSE"				;;
		"STOPPED")	status_printer_state_fr="ARRÊTÉ"				;; 											  
		"FINISHED")	status_printer_state_fr="FINI"					;;
		"IDLE")		status_printer_state_fr="REPOS"				;;
		"")			status_printer_state_fr="HORS LIGNE" && status_printer_state="OFFLINE" ;;
		*)			status_printer_state_fr="$status_printer_state"	;;
	esac
}

get_more_info() {
	echo "Printer State (État de l'imprimante): $status_printer_state / $status_printer_state_fr"
  
	if [ "$status_printer_state" != "OFFLINE" ] ; then
		printer_response=$(curl -H "X-Api-Key: $PRUSALINK_APIKEY" -s $PRINTER_API_URL)
		info_response=$(curl -H "X-Api-Key: $PRUSALINK_APIKEY" -s $INFO_API_URL)
		printer_material=$(echo "$printer_response" | jq -r '.telemetry["material"]')
		info_nozzle_diameter=$(echo "$info_response" | jq -r '.nozzle_diameter')
		
		# Utiliser jq pour extraire et assigner les valeurs de l'API de statut à des variables
		status_time_remaining=$(echo "$status_response" | jq -r '.job.time_remaining')
		status_time_printing=$(echo "$status_response" | jq -r '.job.time_printing')
		status_temp_bed=$(echo "$status_response" | jq -r '.printer.temp_bed')
		status_target_bed=$(echo "$status_response" | jq -r '.printer.target_bed')
		status_temp_nozzle=$(echo "$status_response" | jq -r '.printer.temp_nozzle')
		status_target_nozzle=$(echo "$status_response" | jq -r '.printer.target_nozzle')
		status_axis_z=$(echo "$status_response" | jq -r '.printer.axis_z')
		status_flow=$(echo "$status_response" | jq -r '.printer.flow')
		status_speed=$(echo "$status_response" | jq -r '.printer.speed')
		status_fan_hotend=$(echo "$status_response" | jq -r '.printer.fan_hotend')
		status_fan_print=$(echo "$status_response" | jq -r '.printer.fan_print')
		job_file_display_name=$(echo "$job_response" | jq -r '.file.display_name')
		
		# Fonction pour calculer le pourcentage en évitant la division par zéro et les valeurs vides
		calculate_percentage() {
			local current_temp="$1"
			local target_temp="$2"
			# Vérifiez si les valeurs sont vides ou non définies
			if [ -z "$current_temp" ] || [ -z "$target_temp" ]; then
				echo "0"
			elif [ "$target_temp" -eq 0 ]; then
				echo "0"
			else
				echo "scale=2; ($current_temp / $target_temp) * 100" | bc
			fi
		}
		
		# Assurez-vous que les valeurs sont définies
		status_temp_nozzle="${status_temp_nozzle:-0}"
		status_target_nozzle="${status_target_nozzle:-0}"
		status_temp_bed="${status_temp_bed:-0}"
		status_target_bed="${status_target_bed:-0}"
		# Calculez les pourcentages de chauffe en évitant les divisions par zéro et les valeurs vides
		nozzle_percentage=$(calculate_percentage "$status_temp_nozzle" "$status_target_nozzle")
		bed_percentage=$(calculate_percentage "$status_temp_bed" "$status_target_bed")
		# Arrondissez les pourcentages de chauffe
		nozzle_percentage=$(echo "$nozzle_percentage" | awk '{printf "%.0f\n", $0}')
		bed_percentage=$(echo "$bed_percentage" | awk '{printf "%.0f\n", $0}')

		# Afficher les variables
		if [ -z "$jobstatus" ]; then
			echo "Progress (Progression) : $status_progress %"
			echo " "
			echo "File Display [ID] Name: [$status_job_id] $job_file_display_name"
		fi
		if [ ! "$jobstatus" == "offline" ]; then
			echo " "
			echo "Time Printing (Temps d'impression): $(convertir_temps $status_time_printing)"
			echo "Time Remaining (Temps restant):     $(convertir_temps $status_time_remaining)"
			echo " "
			echo "Temp Nozzle (Température de la buse): $status_temp_nozzle °C / $status_target_nozzle °C ($nozzle_percentage%)"
			echo "Temp Bed (Température du plateau):    $status_temp_bed °C / $status_target_bed °C ($bed_percentage%)"

			echo " "
			echo "Speed (Vitesse d'impression): $status_speed %"
			echo "Flow (Flux d'impression):     $status_flow %"
			echo " "
			echo "Axis Z (Hauteur en z): $status_axis_z mm"
			echo " "
			echo "Fan Hotend (Vitesse du ventilateur de l'extrudeur): $status_fan_hotend tr/min"
			echo "Fan Print (Vitesse du ventilateur l'impression):    $status_fan_print tr/min"
			echo " "
			echo "Material (Matériau): $printer_material"
			echo "Nozzle diameter (Dimètre de buse): $info_nozzle_diameter"
		fi
	fi
}

get_info

case "$1" in
    "pause")
        echo "Printer State: $status_printer_state / $status_printer_state_fr ($status_progress %)"
		if [ -z "$status_job_id" ]; then
            echo "Empty response from the status API."
            exit 1
        fi
        if [ "$status_printer_state" != "PRINTING" ]; then
            echo "Cannot pause job. The printer is not currently printing."
            exit 1
        fi
        pause_job "$status_job_id"
        echo "Job with ID $status_job_id paused."
		get_info
		echo "Printer State: $status_printer_state / $status_printer_state_fr ($status_progress %)"
		sleep 5	;;
    
    "resume")
        echo "Printer State: $status_printer_state / $status_printer_state_fr ($status_progress %)"
		if [ -z "$status_job_id" ]; then
            echo "Empty response from the status API."
            exit 1
        fi
        if [ "$status_printer_state" == "PRINTING" ]; then
            echo "Cannot resume job. The printer is already printing."
            exit 1
        fi
        resume_job "$status_job_id"
        echo "Job with ID $status_job_id resumed."
		get_info
		echo "Printer State: $status_printer_state / $status_printer_state_fr ($status_progress %)"
		sleep 5	;;
		
    "help")
		show_help ;;
		
    "info" | "telemetrie" )
		get_more_info ;;
		
	"remaining" )
		echo "Printer State (État de l'imprimante): $status_printer_state / $status_printer_state_fr"
		status_time_remaining=$(echo "$status_response" | jq -r '.job.time_remaining')
		if [ ! -z "$status_time_remaining" ]; then
			status_time_remaining="1"
		fi
		echo "Time Remaining (Temps restant): $(convertir_temps $status_time_remaining)"
		while true; do echo -n .; sleep 1; done | pv -s $status_time_remaining -S -F '%t %p' > /dev/null ;;
		

	"on" | "poweron" )
		echo "Printer State (État de l'imprimante): $status_printer_state / $status_printer_state_fr"
		if [ "$status_printer_state" == "OFFLINE" ]; then
			echo "	=> POWER ON" 
			$PRUSA_POWERON
		fi ;;
		
	"off" | "poweroff" )
		echo "Printer State (État de l'imprimante): $status_printer_state / $status_printer_state_fr"
		if [ "$status_printer_state" == "OFFLINE" ]; then
			echo "" > /dev/null
												  
			$PRUSA_POWEROFF > /dev/null
																														   
																												  
																						
																					
		elif [ "$status_printer_state" == "IDLE" ] || [ "$status_printer_state" == "STOPPED" ] || [ "$status_printer_state" == "FINISHED" ]; then
			power_off
		else
			echo "Your Prusa is $status_printer_state can power off"
		fi	;;

	"toggle" )
		echo "Printer State (État de l'imprimante): $status_printer_state / $status_printer_state_fr"
		if [ "$status_printer_state" == "OFFLINE" ]; then
			echo "	=> POWER ON" 
			$PRUSA_POWERON
		elif [ "$status_printer_state" == "IDLE" ] || [ "$status_printer_state" == "STOPPED" ] || [ "$status_printer_state" == "FINISHED" ]; then
			power_off
		else
			echo "Your Prusa is $status_printer_state can power off"
		fi	;;
		
	"printer")
        printer_response=$(curl -H "X-Api-Key: $PRUSALINK_APIKEY" -s $PRINTER_API_URL)
		printer_state_text=$(echo "$printer_response" | jq -r '.state.text')
		printer_state_operational=$(echo "$printer_response" | jq -r '.state.flags.operational')
		printer_state_printing=$(echo "$printer_response" | jq -r '.state.flags.printing')
		printer_state_paused=$(echo "$printer_response" | jq -r '.state.flags.paused')
		printer_state_error=$(echo "$printer_response" | jq -r '.state.flags.error')
		echo "Printer State: $printer_state_text"
		echo " "
		echo "Operational: $printer_state_operational"
		echo "Printing:    $printer_state_printing"
		echo "Paused:      $printer_state_paused"
		echo "Error:       $printer_state_error"
        ;;
		
	"debug")
		echo "Fetching status JSON..."
		status_response=$(curl -H "X-Api-Key: $PRUSALINK_APIKEY" -s $STATUS_API_URL)
		echo "Status JSON:"
		echo "$status_response" | jq .
		echo ""
		echo "Fetching job JSON..."
		job_response=$(curl -H "X-Api-Key: $PRUSALINK_APIKEY" -s $JOB_API_URL)
		echo "Job JSON:"
		echo "$job_response" | jq .
		echo ""
		echo "Fetching printer JSON..."
		printer_response=$(curl -H "X-Api-Key: $PRUSALINK_APIKEY" -s $PRINTER_API_URL)
		echo "Printer JSON:"
		echo "$printer_response" | jq .
		echo ""
		echo "Fetching info JSON..."
		info_response=$(curl -H "X-Api-Key: $PRUSALINK_APIKEY" -s $INFO_API_URL)
		echo "Info JSON:"
		echo "$info_response" | jq .
        ;;
		
	#ESP32CAM Intégration 
    "capture") 		curl "http://$ESP32CAM_IP/action_capture" ;;
    "send") 		curl "http://$ESP32CAM_IP/action_send" ;;
    "light_on") 	curl "http://$ESP32CAM_IP/light?on" ;;
    "light_off") 	curl "http://$ESP32CAM_IP/light?off" ;;
    "flash_on") 	curl "http://$ESP32CAM_IP/flash?on" ;;
    "flash_off") 	curl "http://$ESP32CAM_IP/flash?off" ;;
    "reboot") 		curl "http://$ESP32CAM_IP/action_reboot" ;;
    "cam_logs") 	curl "http://$ESP32CAM_IP/get_logs" ;;
    "last_photo") 	echo "http://$ESP32CAM_IP/saved-photo.jpg" ;; ###@@@### UTILE ???
	"send_light")
		curl "http://$ESP32CAM_IP/light?on"
		curl "http://$ESP32CAM_IP/action_send"
		sleep 1
		curl "http://$ESP32CAM_IP/light?off"
		echo "http://$ESP32CAM_IP/saved-photo.jpg"
		;;
		
	*)
		show_help
		echo "" && echo "______________________________________" &&	echo ""
		get_more_info ;; 
esac
