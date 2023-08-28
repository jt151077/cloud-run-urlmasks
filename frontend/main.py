import os
from flask import Flask, jsonify, request, render_template
import urllib, json, requests
import subprocess


app = Flask(__name__)


@app.route("/",methods=['GET','POST'])
def index():
    if request.method=='GET':
        return render_template ("index.html", codes="{'data': 'no-data'}")    

    else:
        return jsonify({'Error':"This is a GET API method"})



@app.route("/<servicenumber>",methods=['GET','POST'])
def service(servicenumber):
    if request.method=='GET':

        resp = requests.get("http://private.jeremyto.demo.altostrat.com/pri/runservice{}".format(servicenumber))
        d = ""

        try:
            d = resp.json()
        except:
            d = resp

        return render_template ("index.html", codes=d)    

    else:
        return jsonify({'Error':"This is a GET API method"})

