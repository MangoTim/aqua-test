from flask import Flask, render_template

app = Flask(__name__)

@app.route('/')
def welcome():
    return render_template('welcome.html')

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8083)

# touch Fri, Oct  2, 2026 10:18:33 AM
# touch Fri, Oct  2, 2026 10:18:56 AM
# touch Fri, Oct  2, 2026 10:44:27 AM
