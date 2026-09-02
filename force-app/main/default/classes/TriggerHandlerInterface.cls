/**
 * File Name   :	TriggerHandlerInterface.cls
 * Description :	An interface defining the contract for trigger handler classes, facilitating the implementation of custom logic for Salesforce triggers.
 **/
public interface TriggerHandlerInterface {
    /**
     * Designed to execute custom logic within trigger handler classes, enabling the processing of old and new records along with their corresponding maps in Salesforce triggers.
     */
    void execute();
}