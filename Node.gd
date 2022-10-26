extends Node

const FIRST_NOTICE_TIMEOUT = 3000

var ip = "192.168.1.32"
var client :StreamPeerTCP
var nick = "GodotIRC0"
var channel = "#test"
var password = "secret"+nick

onready var messageEditor = $Panel/iRCContainer/chatContainer/FieldContainer/enterLine
onready var whisperLabel = $Panel/iRCContainer/chatContainer/FieldContainer/WhisperLabel
onready var rmbPopupMenu = $RMBPopupMenu
onready var iRCDisplayer = $Panel/iRCContainer/chatContainer/text
onready var userList = $Panel/iRCContainer/UserList

var time

var lt = RichTextLabel.new()
var initializing = true
var status = CONNECTION_STAGE.DISCONNECTED
var users := []

var whisper_mode = false
var whisper_username = ""

enum CONNECTION_STAGE {
	DISCONNECTED,
	FAILED_TO_CONNECT,
	WAIT_BEFORE_RECONNECTION,
	JUST_CONNECTED,
	FIRST_NOTICE_OBTAINED,
	SECOND_NOTICE_OBTAINED,
	REGISTERING,
	REGISTERED,
	NICKNAMED,
	WAIT_BEFORE_JOINING_CHANNEL,
	WAIT_AFTER_JOINING_CHANNEL,
	FULLY_CONNECTED
	
	
}

func add_user(username : String):
	username = username.strip_edges()
	for i in range(0, userList.get_item_count()):
		print("'", userList.get_item_text(i), "' '", username, "'")
		if username == userList.get_item_text(i):
			print("returning")
			return
	users.push_back(username)
	userList.add_item(username)

func remove_user(username : String):
	users.erase(username)
	for i in range(0, userList.get_item_count()):
		if username == userList.get_item_text(i):
			userList.remove_item(i)
	

func print_in_chat(text : String):
	iRCDisplayer.append_bbcode("[" + time + "]: " + text + "\n")
	iRCDisplayer.scroll_to_line(iRCDisplayer.get_line_count()-1)
	print(iRCDisplayer.get_line_count())
#	vscroll.value = vscroll.max_value

func _ready():
	_on_time_updater_timeout()
	rmbPopupMenu.add_item("Copy")
	rmbPopupMenu.add_item("Whisper")

#	if password != "":
#		client.put_data(("JOIN "+ password +"\n").to_utf8())
	self.add_child(sequence_timer)
#	client.put_data(("USER "+ nick +" "+ nick +" "+ nick +" :TEST\n").to_utf8())
#	client.put_data(("NICK "+ nick +"\n").to_utf8())
#	client.put_data(("JOIN "+ channel +"\n").to_utf8())
	set_process(true)

func enable_whisper_mode(username : String):
	whisper_mode = true
	whisper_username = username
	whisperLabel.text = "Whispering @" + username

func disable_whisper_mode():
	whisper_mode = false
	whisper_username = ""
	whisperLabel.text = ""
	

func try_connect_to_irc_host():
	if (client and client.is_class("StreamPeerTCP") 
		and client.is_connected_to_host()):
			client.disconnect_from_host()
	client = StreamPeerTCP.new()
	var err = client.connect_to_host(ip, 6667)
	return err

var sequence_timer := Timer.new()

func launch_wait_timer_if_stopped(seconds : float):
	if sequence_timer.is_stopped():
		launch_wait_timer(seconds)

func launch_wait_timer(seconds : float):
	sequence_timer.stop()
	sequence_timer.set_wait_time(seconds)
	sequence_timer.set_one_shot(true)
	sequence_timer.start()
	

func read_responses() -> Array:
	if ((client.get_status() == StreamPeerTCP.STATUS_CONNECTED) 
		&& (client.get_available_bytes() > 0)):
		
		var r_string := str(client.get_utf8_string(client.get_available_bytes()))
		var r = r_string.split('\n')
#		print(r_string)		for line in response:
		for line in r:
			
			var words = line.split(' ')
			if (words.size() > 1):
				if words[1] == "353":
					print(line)			
		return r
	else:
		return []

var response = []

func consume_response():
	response.remove(0)

func _process(_delta):
	if status == CONNECTION_STAGE.DISCONNECTED:
		print_in_chat("Connecting to chat...")
		var err = try_connect_to_irc_host()
		if err == FAILED:
			status = CONNECTION_STAGE.FAILED_TO_CONNECT
		elif err == OK:
			status = CONNECTION_STAGE.JUST_CONNECTED
			launch_wait_timer_if_stopped(FIRST_NOTICE_TIMEOUT/1000.0)
		else:
			assert(not "unknown error, this shouldn't happen")
	else:
		var r = read_responses()
#		print(r)
		if not r.empty():
			for line in r:
				response.push_back(line)
#		if not response.empty():
#			print(response)
		while response.size() > 0:
#			print(line)
			var line = response[0]
			var words = line.split(' ')
			if (words.size() > 1) and (words[0] == "ERROR"):
					client.disconnect_from_host()
					status = CONNECTION_STAGE.FAILED_TO_CONNECT
					print_in_chat("Disconnected from server")
					print("Disconnected from server")
					print_in_chat(str(response))
					consume_response()
			elif (words.size() > 5) and (words[1] == "353"):
					words[5] = words[5].substr(1)
					for i in range(5, words.size()):
						add_user(words[i])
					consume_response()
			elif (words.size() > 1) and (words[0] == "PING"):
					print(words)
					var err = client.put_data(("PONG "+ str(words[1]) +"\n").to_utf8())
					if err != OK:
						print_in_chat("Failed to answer PONG")
						status = CONNECTION_STAGE.DISCONNECT
					print("PONG "+ str(words[1]) +"\n")
					consume_response()
					
			
			elif ((status == CONNECTION_STAGE.JUST_CONNECTED) and
				(line.find("NOTICE * :*** Looking up your hostname...") != -1)):
					consume_response()
					status = CONNECTION_STAGE.FIRST_NOTICE_OBTAINED
					print("first notice")
					
			elif ((status == CONNECTION_STAGE.JUST_CONNECTED) and
				(line.find("ERROR") != -1)):
					consume_response()
					status = CONNECTION_STAGE.FAILED_TO_CONNECT
					printerr("Failed to connect to chat server")
					print("first notice")
					
			elif ((status == CONNECTION_STAGE.FIRST_NOTICE_OBTAINED) and
				(line.find("NOTICE * :***") != -1)):
					consume_response()
					status = CONNECTION_STAGE.REGISTERING
					print("second notice")
					
			elif ((status == CONNECTION_STAGE.REGISTERING) and
				(line.find("You may not reregister") != -1)):
					consume_response()
					status = CONNECTION_STAGE.REGISTERED
					

#					words[4].substr(1)
#					for i in range(4, words.size()):
#						print(words[i])
#						add_user(words[i])
#					consume_response()
			elif (words.size() > 1) and words[1] == "PRIVMSG":
					print("message recieved")
					var text = ""
					for i in range (3, words.size()):
						text += words[i] + " "
					text = text.substr(1, text.length()-1)
					lt.clear()
					print_in_chat(get_name_user(words[0]) + "> " + str(text))
					consume_response()
					
			elif (words.size() > 2) and (words[1] == "NOTICE"):
					var text = ""
					for i in range (4, words.size()):
						text += words[i] + " "
					print_in_chat("[i] [color=green]SERVER:[/color] " + text + "[/i]")
					consume_response()
					
			elif (words.size() > 2) and (words[1] == "JOIN"):
					print_in_chat("[i] [color=red]==[/color] " + get_name_user(words[0]) + " has joined " + str(channel) + "[/i]")
					add_user(get_name_user(words[0]))
					consume_response()
					
			elif (words.size() > 2) and (words[1] == "QUIT"):
					var text = ""
					for i in range (4, words.size()):
						text += words[i] + " "
					print_in_chat("[i] == " + get_name_user(words[0]) + " QUIT (" + str(text) + ")[/i]")
					remove_user(get_name_user(words[0]))
					consume_response()
					
			elif (words.size() > 2) and (words[1] == "PART"):
					print_in_chat("[i] == " + get_name_user(words[0]) + " has left " + str(channel) + "[/i]")
					consume_response()
			
			else:
#				print("UNHANDLED: " + str(line.split('\n')))
				consume_response()
		if status == CONNECTION_STAGE.FAILED_TO_CONNECT:
			launch_wait_timer(2)
			status = CONNECTION_STAGE.WAIT_BEFORE_RECONNECTION
		elif CONNECTION_STAGE.WAIT_BEFORE_RECONNECTION == status: 
			yield(sequence_timer, "timeout")
			if CONNECTION_STAGE.WAIT_BEFORE_RECONNECTION == status:
				status = CONNECTION_STAGE.DISCONNECTED
				print_in_chat("Failed to connect, reconnecting...")
		elif CONNECTION_STAGE.JUST_CONNECTED == status:
			print("Waiting for first notice...")
			yield(sequence_timer, "timeout")
			status = CONNECTION_STAGE.FAILED_TO_CONNECT
		
		elif CONNECTION_STAGE.REGISTERING == status:
			var err = client.put_data(("/msg NickServ register" + password + " " + "a@a.a" + "\n").to_utf8())
			if err != OK:
				print_in_chat("Failed to register")
				status = CONNECTION_STAGE.FAILED_TO_CONNECT
			err = client.put_data(("USER " + nick + " " +nick + " " +nick + " " + nick + "\n").to_utf8())
			if err != OK:
				print_in_chat("Failed to identify self to server")
				status = CONNECTION_STAGE.FAILED_TO_CONNECT
			else:
				status = CONNECTION_STAGE.REGISTERED
	#		client.put_data(("JOIN "+ channel +"\n").to_utf8())
		elif CONNECTION_STAGE.REGISTERED == status:
			print("registered")
			var err = client.put_data(("NICK "+ nick +"\n").to_utf8())
			if err != OK:
				print_in_chat("Failed to declare nickname")
				status = CONNECTION_STAGE.FAILED_TO_CONNECT
			else:
				status = CONNECTION_STAGE.WAIT_BEFORE_JOINING_CHANNEL
				launch_wait_timer_if_stopped(0.25)
		elif CONNECTION_STAGE.WAIT_BEFORE_JOINING_CHANNEL == status:
			yield(sequence_timer, "timeout")
			status = CONNECTION_STAGE.NICKNAMED
		elif CONNECTION_STAGE.NICKNAMED == status:
			print("nicknamed")
			var err = client.put_data(("JOIN "+ channel +"\n").to_utf8())
			if err != OK:
				print_in_chat("Failed to join channel")
				status = CONNECTION_STAGE.FAILED_TO_CONNECT
			else:
				launch_wait_timer_if_stopped(0.25)
				status = CONNECTION_STAGE.WAIT_AFTER_JOINING_CHANNEL
		elif CONNECTION_STAGE.WAIT_AFTER_JOINING_CHANNEL == status:
			yield(sequence_timer, "timeout")
			if CONNECTION_STAGE.WAIT_AFTER_JOINING_CHANNEL == status:
				status = CONNECTION_STAGE.FULLY_CONNECTED
				print_in_chat("[b]Connected to chat server[/b]")
		elif CONNECTION_STAGE.FULLY_CONNECTED == status:
			if not ((client.get_status() == StreamPeerTCP.STATUS_CONNECTED)):
				print_in_chat("Connection dropped")
				status = CONNECTION_STAGE.FAILED_TO_CONNECT
				



func get_name_user (value):
	var a = value.find("!")
	return value.substr(1, a-1)

func _on_enterLine_text_entered( text ):
	lt.clear()
	lt.append_bbcode(text)
	print_in_chat("<" + nick + "> " + str(lt.get_text()))
	var err
	if whisper_mode:
		# not working =(
		err = client.put_data(("PRIVMSG " + whisper_username + " '" + str(lt.get_text()) +"'\n").to_utf8())
		print("/msg " + whisper_username + " " + str(lt.get_text()) +"\n")
	else:
		err = client.put_data(("PRIVMSG "+ channel + " :" + str(lt.get_text()) +"\n").to_utf8())
		print("PRIVMSG "+ channel + " :" + str(lt.get_text()))
	if err != OK:
		print_in_chat("Failed to send message")
		status = CONNECTION_STAGE.FAILED_TO_CONNECT

	messageEditor.clear()

func _on_Button_pressed():
	_on_enterLine_text_entered(messageEditor.get_text())


func _on_time_updater_timeout():
	time = ""
	if OS.get_time().hour < 10:
		time += "0"
	time += str(OS.get_time().hour) + ":"
	
	if OS.get_time().minute < 10:
		time += "0"
	time += str(OS.get_time().minute) + ":"
	
	if OS.get_time().second < 10:
		time += "0"
	time += str(OS.get_time().second)

func _exit_tree():
	client.disconnect_from_host()
	



func _on_enterLine_gui_input(event : InputEvent):
	if whisper_mode:
		if messageEditor.caret_position == 0 :
			if event is InputEventKey:
				if event.get_scancode_with_modifiers() == KEY_BACKSPACE:
					disable_whisper_mode()
	pass # Replace with function body.


var buffered_userlist_username

func _on_UserList_item_rmb_selected(index, at_position):
		buffered_userlist_username = userList.get_item_text(index)
		print("pop")
		var last_mouse_position = rmbPopupMenu.get_global_mouse_position()
		rmbPopupMenu.popup(Rect2(last_mouse_position, rmbPopupMenu.rect_size))
				


func _on_RMBPopupMenu_id_pressed(id):
	if id == 0:
		OS.set_clipboard(buffered_userlist_username)
	elif id == 1:
		enable_whisper_mode(buffered_userlist_username)
