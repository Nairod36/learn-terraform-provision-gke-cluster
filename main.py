import requests

def main(request):
 
    nginx_url = "http://<ADRESSE_IP_PUBLIQUE_DE_VOTRE_NGINX>/" 
    try:
        response = requests.get(nginx_url)
        return f"Status Code: {response.status_code}, Response: {response.text}"
    except requests.exceptions.RequestException as e:
        return f"Error: {e}"
