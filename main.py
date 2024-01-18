import requests

def main(request):
 
    nginx_url = "http://34.123.129.36:80/" 
    try:
        response = requests.get(nginx_url)
        return f"Status Code: {response.status_code}, Response: {response.text}"
    except requests.exceptions.RequestException as e:
        return f"Error: {e}"
