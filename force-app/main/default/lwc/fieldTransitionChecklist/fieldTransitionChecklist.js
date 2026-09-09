import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getPendingRequirements from '@salesforce/apex/FieldTransitionRequirementController.getPendingRequirements';
import checklistTitle from '@salesforce/label/c.Field_Transition_Checklist_Title';
import emptyStateMessage from '@salesforce/label/c.Field_Transition_Checklist_Empty_State';

export default class FieldTransitionChecklist extends LightningElement {
    @api recordId;

    label = {
        checklistTitle,
        emptyStateMessage
    };

    groups = [];
    error;
    isLoading = true;
    wiredResult;

    @wire(getPendingRequirements, { recordId: '$recordId' })
    wiredRequirements(result) {
        this.wiredResult = result;
        this.isLoading = false;
        if (result.data) {
            this.groups = result.data.map((group) => this.decorateGroup(group));
            this.error = undefined;
        } else if (result.error) {
            this.error = this.extractErrorMessage(result.error);
            this.groups = [];
        }
    }

    get hasGroups() {
        return this.groups.length > 0;
    }

    get showEmptyState() {
        return !this.isLoading && !this.error && !this.hasGroups;
    }

    handleRefresh() {
        this.isLoading = true;
        refreshApex(this.wiredResult).finally(() => {
            this.isLoading = false;
        });
    }

    decorateGroup(group) {
        return {
            ...group,
            key: group.fieldApiName,
            transitions: group.transitions.map((transition) => this.decorateTransition(transition))
        };
    }

    decorateTransition(transition) {
        return {
            ...transition,
            key: transition.toValue,
            statusIcon: transition.allSatisfied ? 'utility:success' : 'utility:warning',
            statusVariant: transition.allSatisfied ? 'success' : 'warning',
            conditions: transition.conditions.map((condition) => ({
                ...condition,
                key: transition.toValue + '-' + condition.label,
                statusIcon: condition.satisfied ? 'utility:success' : 'utility:close',
                statusVariant: condition.satisfied ? 'success' : 'error'
            }))
        };
    }

    extractErrorMessage(error) {
        if (error && error.body && error.body.message) {
            return error.body.message;
        }
        return 'An unexpected error occurred while loading the checklist.';
    }
}
