import os
from flask import Flask, jsonify, request
import urllib, json, requests
app = Flask(__name__)


@app.route("/pri/runservice3",methods=['GET','POST'])
def runservice1():
    if request.method=='GET':
        
        #resp = requests.get("http://private.jeremyto.demo.altostrat.com/pri/runservice1")
        resp = requests.get("https://jsonplaceholder.typicode.com/users")
        d = {}

        try:
            d = resp.json()
        except:
            d = resp
              
        return jsonify(d)
    else:
        return jsonify({'Error':"This is a GET API method"})


if __name__ == "__main__":
    app.run(debug=True, host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))