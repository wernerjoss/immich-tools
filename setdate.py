#!/usr/bin/env python3
# Set Date for selected Files, e.g. scanned Fotos...

# see https://www.pythontutorial.net/pyqt/pyqt-qfiledialog/

import os, sys
import yaml
from PyQt5.QtCore import Qt, QProcess
from PyQt5.QtWidgets import QApplication,  QFileDialog, QWidget, QGridLayout, QListWidget, QPushButton, QLabel, QLineEdit, QMessageBox
from pathlib import Path

class MainWindow(QWidget):
	def setpath(self):
		try:
			if (self.yaml_data["path"]) :
				path = str(self.yaml_data["path"])
		except KeyError:
			path = str(Path.home())

		return path
		
	def save_yaml(self):
		self.yaml_data["PicDir"] = self.pic_dir_edit.text()
		self.yaml_data["path"] = self.setpath()
		with open(self.yaml_file, "w") as f:
		    yaml.dump(self.yaml_data, f)

	def load_yaml(self):
		try:
			with open(self.yaml_file, "r") as f:
				return yaml.safe_load(f)
		except FileNotFoundError:
			path = str(Path.home())
			return {"PicDir": path, "path": path}
				
	def __init__(self, *args, **kwargs):
		super().__init__(*args, **kwargs)

		self.setWindowTitle('PyQt File-Date Change Dialog')
		self.setGeometry(100, 100, 1280, 100)

		layout = QGridLayout()
		self.setLayout(layout)

		cfgpath = os.path.abspath(os.path.dirname(__file__))
		
		self.yaml_file = cfgpath + "/setdate.yaml"
		# print(self.yaml_file)
		self.yaml_data = self.load_yaml()
		# print(self.yaml_data["PicDir"])
		self.pic_dir_edit = QLineEdit(self.yaml_data["PicDir"])
        
		# file selection
		file_browse = QPushButton('Select Files')
		file_browse.clicked.connect(self.open_file_dialog)

		# Date Edit
		self.dateEdit = QLineEdit('1989-05-12 11:30')
		
		self.file_list = QListWidget(self)
		
		self.btn = QPushButton("Execute")
		self.btn.pressed.connect(self.start_process)
        
		layout.addWidget(QLabel('Target Folder:'), 0, 0)
		layout.addWidget(self.pic_dir_edit, 1, 0)
		# self.pic_dir_edit.setFixedHeight(30);
		layout.addWidget(file_browse, 2, 0)
		layout.addWidget(QLabel('Target Date:'), 3, 0)
		layout.addWidget(self.dateEdit, 4, 0)
		layout.addWidget(self.btn, 5, 0)
		layout.addWidget(QLabel('Commands Created:'), 6, 0)
		layout.addWidget(self.file_list, 7, 0)
		self.file_list.setFixedHeight(650);
		
		self.show()

	def start_process(self):
		# self.message("Executing process.")
		self.p = QProcess()  # Keep a reference to the QProcess (e.g. on self) while it's running.
		doit = self.setpath()  + '/doit.sh'
		# print(doit)
		self.p.start("/bin/bash", [doit])
		# Show a message box to indicate that the Action has been started
		msg_box = QMessageBox()
		msg_box.setText(doit + " has been started.")
		msg_box.exec()
		self.file_list.clear()
		

	def open_file_dialog(self):
		self.path = str(self.pic_dir_edit.text())	#	"/home/josswern/Bilda/Dia-Scans/"
		#dir_name = QFileDialog.getExistingDirectory(self, "Select a Directory")
		#if dir_name:
		#	path = str(Path(dir_name)) + "/"
			# self.dir_name_edit.setText(str(path))
		# print(path)	
		filenames, _ = QFileDialog.getOpenFileNames(
			self,
			"Select Files",self.path,	# 	/home/josswern/tmp/resize
			"Images (*.png *.jpg)"
		)
		if filenames:
			d = self.dateEdit.text()
			d = d.replace("-", "")	# allow readable date notation, strip separators later
			d = d.replace(" ", "")
			d = d.replace(":", "")
			self.file_list.addItems(["touch -t " + d + " " + str(filename)
									 for filename in filenames])
			# file_list is a QListWidget full of items
			jpg_items = self.file_list.findItems(".jpg", Qt.MatchContains)
			png_items = self.file_list.findItems(".png", Qt.MatchContains)
			all_items = jpg_items + png_items
			print(str(all_items[0]))
			
			# print(self.path)
			self.save_yaml()
			self.pic_dir_edit.text = self.path
			with open(self.setpath() + '/doit.sh', 'w') as shellFile:
				for item in all_items:
					shellFile.write(item.text() + "\n")
			
if __name__ == '__main__':
	app = QApplication(sys.argv)
	window = MainWindow()
	sys.exit(app.exec())