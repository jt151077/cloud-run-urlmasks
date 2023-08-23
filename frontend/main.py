import os
from flask import Flask, jsonify, request, render_template
import urllib.request, json
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

        url = "https://run.jeremyto.demo.altostrat.com/runservice{}".format(servicenumber)

        response = urllib.request.urlopen(url)
        data = response.read()
        d = ""

        try:
            d = json.loads(data)
        except:
            d = data

        return render_template ("index.html", codes=d)    

    else:
        return jsonify({'Error':"This is a GET API method"})

