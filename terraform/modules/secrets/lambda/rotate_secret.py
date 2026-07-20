"""
Secrets Manager single-user rotation Lambda.

Implements the standard 4-step rotation contract Secrets Manager expects:
createSecret -> setSecret -> testSecret -> finishSecret.

set_secret and test_secret are intentionally no-ops right now: there is no
live database yet for this credential to actually authenticate against
(that arrives in Phase 5/6). This still proves the real mechanism -
Secrets Manager calling this function, a new password being generated,
correctly versioned through AWSPENDING -> AWSCURRENT, and the whole thing
either succeeding or raising - which is exactly what the EventBridge
failure pipeline in block B watches for.

Once a real database exists, set_secret gains an ALTER USER ... PASSWORD
call using the AWSCURRENT credentials to authenticate, and test_secret
gains an actual login attempt with the AWSPENDING credentials.
"""
import json
import secrets as pysecrets
import string

import boto3


def lambda_handler(event, context):
    arn = event["SecretId"]
    token = event["ClientRequestToken"]
    step = event["Step"]

    client = boto3.client("secretsmanager")
    metadata = client.describe_secret(SecretId=arn)

    if not metadata["RotationEnabled"]:
        raise ValueError(f"Secret {arn} is not enabled for rotation")

    versions = metadata["VersionIdsToStages"]
    if token not in versions:
        raise ValueError(f"Secret version {token} has no stage for rotation of {arn}")
    if "AWSCURRENT" in versions[token]:
        return
    if "AWSPENDING" not in versions[token]:
        raise ValueError(f"Secret version {token} not set as AWSPENDING for {arn}")

    if step == "createSecret":
        create_secret(client, arn, token)
    elif step == "setSecret":
        set_secret(client, arn, token)
    elif step == "testSecret":
        test_secret(client, arn, token)
    elif step == "finishSecret":
        finish_secret(client, arn, token)
    else:
        raise ValueError(f"Invalid step: {step}")


def create_secret(client, arn, token):
    current = json.loads(
        client.get_secret_value(SecretId=arn, VersionStage="AWSCURRENT")["SecretString"]
    )
    try:
        client.get_secret_value(SecretId=arn, VersionId=token, VersionStage="AWSPENDING")
    except client.exceptions.ResourceNotFoundException:
        alphabet = string.ascii_letters + string.digits
        new_password = "".join(pysecrets.choice(alphabet) for _ in range(24))
        new_secret = dict(current)
        new_secret["password"] = new_password
        client.put_secret_value(
            SecretId=arn,
            ClientRequestToken=token,
            SecretString=json.dumps(new_secret),
            VersionStages=["AWSPENDING"],
        )


def set_secret(client, arn, token):
    # No live backing store to push the new password to yet - see module
    # docstring. This is where the ALTER USER call goes once one exists.
    pass


def test_secret(client, arn, token):
    # No live backing store to test a login against yet - see module
    # docstring. This is where a real connection attempt goes once one
    # exists, using the AWSPENDING credentials.
    pass


def finish_secret(client, arn, token):
    metadata = client.describe_secret(SecretId=arn)
    current_version = None
    for version, stages in metadata["VersionIdsToStages"].items():
        if "AWSCURRENT" in stages:
            if version == token:
                return
            current_version = version
            break

    client.update_secret_version_stage(
        SecretId=arn,
        VersionStage="AWSCURRENT",
        MoveToVersionId=token,
        RemoveFromVersionId=current_version,
    )
