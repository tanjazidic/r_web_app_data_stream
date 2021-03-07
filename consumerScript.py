from confluent_kafka import Consumer
import pandas as pd
import json
from pandas.io.json import json_normalize
import uuid
import kafka




def translated():
    return True
def get_df(c):
	while True:
		try:
			msg = c.poll()
			#print('Received message: {}'.format(msg.value().decode('utf-8')))
			#print('msg partition: {}'.format(msg.partition()))
			#print('msg offset: {}'.format(msg.offset()))
			data = json.loads(msg.value())
			df = pd.DataFrame.from_dict(json_normalize(data), orient='columns')
			return df
		except:
			continue
def close():
	c.close()
def create_consumer(topicName,bootstrapServer):
	c = Consumer({
		'bootstrap.servers': bootstrapServer,
		'group.id': str(uuid.uuid4()) ,
		'default.topic.config': {'auto.offset.reset': 'smallest'}
	})
	c.subscribe([topicName]) 
	return c

def check_topic(bootstrapServer,topicName):
	consumer = kafka.KafkaConsumer(group_id=str(uuid.uuid4()), bootstrap_servers=bootstrapServer)
	topics=consumer.topics()
	if topicName in topics:
		return True
	else:
		return False